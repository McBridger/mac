import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import Combine
import CoreModels

// Класс должен быть NSObject, чтобы быть делегатом, и ObservableObject для удобства
public class BluetoothManager: NSObject, CBPeripheralManagerDelegate, ObservableObject {

    // MARK: - Public Publishers
    @State public private(set) var power: BluetoothPowerState = .poweredOff
    @State public private(set) var connection: ConnectionState = .disconnected
    @State public private(set) var devices: [DeviceInfo] = []
    public var messages: AnyPublisher<BridgerMessage, Never> { messageSubject.eraseToAnyPublisher() }

    // MARK: - Private State
    private var devicesMap: [UUID: DeviceInfo] = [:]
    private var textCharacteristic: CBMutableCharacteristic?
    private var nameRequestTasks: [UUID: Timer] = [:]
    private let nameRequestTimeout: TimeInterval = 5.0

    // MARK: - Private Combine Subjects & Cancellables
    private let messageSubject = PassthroughSubject<BridgerMessage, Never>()
    private let sendSubject = PassthroughSubject<BridgerMessage, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CoreBluetooth Properties
    // Все вызовы CoreBluetooth будут выполняться на этой очереди
    private let queue = DispatchQueue(label: "com.mcbridge.bluetooth-background-queue")
    private lazy var peripheralManager: CBPeripheralManager = {
        CBPeripheralManager(delegate: self, queue: self.queue)
    }()
    
    private let advertiseUUID = CBUUID(string: "fdd2")
    private let bridgerServiceUUID = CBUUID(string: "ccfa23b4-ba6f-448a-827d-c25416ec432e")
    private let characteristicUUID = CBUUID(string: "315eca9d-0dbc-498d-bb4d-1d59d7c5bc3b")

    // MARK: - Lifecycle
    public override init() {
        super.init()
        
        queue.async { _ = self.peripheralManager }

        sendSubject
            .receive(on: queue)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard self.power == .poweredOn else { return }
                guard !self.devicesMap.isEmpty else { return }
                guard let char = self.textCharacteristic else { return }
                guard let data = message.toData() else { return }

                self.peripheralManager.updateValue(data, for: char, onSubscribedCentrals: nil)
                Logger.bluetooth.info("Sent a message of type \(message.type.rawValue) by command.")

            }
            .store(in: &cancellables)
    }
    
    public func send(message: BridgerMessage) {
        sendSubject.send(message)
    }

    // MARK: - Delegate Methods (ВЫПОЛНЯЮТСЯ НА НАШЕЙ `queue`)
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let newState: BluetoothPowerState = (peripheral.state == .poweredOn) ? .poweredOn : .poweredOff
        if self.power == newState { return }
        updateState(state: &self.power, to: newState)
        Logger.bluetooth.info("Bluetooth state changed: \(self.power.rawValue)")

        if self.power == .poweredOn { setupService(); return }
        
        devicesMap.removeAll()
        nameRequestTasks.values.forEach { $0.invalidate() }
        nameRequestTasks.removeAll()
        updateState(state: &self.connection, to: .disconnected)
        reportUpdatedDeviceList()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error adding service: \(error.localizedDescription)")
            return
        }
        startAdvertising()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let centralId = central.identifier
        guard devicesMap[centralId] == nil else { return }
        
        let isFirstDevice = devicesMap.isEmpty
        let newDevice = DeviceInfo(id: centralId, name: "Unknown soldier...")
        devicesMap[centralId] = newDevice
        
        if isFirstDevice { updateState(state: &self.connection, to: .connected) }
        
        Logger.bluetooth.info("Anonymus connected: \(centralId.uuidString). Waiting for him to introduce himself.")
        
        let timer = Timer.scheduledTimer(
            withTimeInterval: nameRequestTimeout, 
            repeats: false
        ) { [weak self] _ in
            self?.handleDeviceTimeout(centralId)
        }
        nameRequestTasks[centralId] = timer
        
        reportUpdatedDeviceList()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralId = central.identifier
        if let disconnectedDevice = devicesMap.removeValue(forKey: centralId) {
            nameRequestTasks[centralId]?.invalidate()
            nameRequestTasks.removeValue(forKey: centralId)
            
            Logger.bluetooth.info("Device \(disconnectedDevice.name) (\(centralId.uuidString)) has ridden off into the sunset.")

            if devicesMap.isEmpty {
                updateState(state: &self.connection, to: .advertising)
            }
            
            reportUpdatedDeviceList()
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else { return }
        
        handleWrite(value: value, from: request.central.identifier)
        peripheral.respond(to: request, withResult: .success)
    }
    
    // MARK: - Private Logic (все вызываются изнутри `queue`)
    
    private func setupService() {
        let service = CBMutableService(type: bridgerServiceUUID, primary: true)
        self.textCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        service.characteristics = [self.textCharacteristic!]
        peripheralManager.add(service)
    }
    
    private func startAdvertising() {
        guard self.connection != .advertising else { return }
        
        let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "McBridge"
        let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [advertiseUUID],
          CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        updateState(state: &self.connection, to: .advertising)
        Logger.bluetooth.info("Started yelling on the air with the handle \(deviceName).")
    }
    
    private func handleWrite(value: Data, from centralID: UUID) {
        do {
            let message = try BridgerMessage.fromData(value, address: centralID.uuidString)
            Logger.bluetooth.info("Message decrypted: Type \(message.type.rawValue), value: '\(message.value)'")
            
            switch message.type {
            case .DEVICE_NAME:
                handleDeviceNamed(id: centralID, name: message.value)
            case .CLIPBOARD:
                messageSubject.send(message)
            }
        } catch {
            Logger.bluetooth.error("Error decoding data from \(centralID.uuidString): \(error.localizedDescription)")
        }
    }
    
    private func handleDeviceNamed(id: UUID, name: String) {
        devicesMap[id]?.name = name
        nameRequestTasks[id]?.invalidate()
        nameRequestTasks.removeValue(forKey: id)
        Logger.bluetooth.info("Device \(id.uuidString) has introduced itself as \(name). Nice to meet you.")
        reportUpdatedDeviceList()
    }

    private func handleDeviceTimeout(_ deviceId: UUID) {
        if let timedOutDevice = devicesMap[deviceId], timedOutDevice.name == "Unknown soldier..." {
            Logger.bluetooth.warning("Device \(deviceId.uuidString) timed out without introducing itself. Presumed shy.")
        }
        nameRequestTasks.removeValue(forKey: deviceId)
    }

    private func reportUpdatedDeviceList() {
        let sortedDevices = Array(devicesMap.values).sorted { $0.name < $1.name }
        self.devices = sortedDevices
        Logger.bluetooth.debug("Sending updated device list: \(sortedDevices.count) devices")
    }

    private func updateState<T: Equatable>(state: inout T, to newValue: T) {
        guard state != newValue else { return }
        state = newValue
    }
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let bluetooth = Logger(subsystem: subsystem, category: "BluetoothManager")
}
