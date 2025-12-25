import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import Combine
import CoreModels

public class BluetoothManager: NSObject, CBPeripheralManagerDelegate, ObservableObject {

    // MARK: - Public Publishers
    @State public private(set) var power: BluetoothPowerState = .poweredOff
    @State public private(set) var connection: ConnectionState = .disconnected
    @State public private(set) var devices: [DeviceInfo] = []
    @Event public private(set) var message: BridgerMessage?

    // MARK: - Private State
    private var connections: [UUID: (device: DeviceInfo, central: CBCentral)] = [:]
    private var textCharacteristic: CBMutableCharacteristic?
    private var nameRequestTasks: [UUID: DispatchSourceTimer] = [:]
    private let nameRequestTimeout: TimeInterval = 5.0

    // MARK: - Private Combine Subjects & Cancellables
    private let sendSubject = PassthroughSubject<BridgerMessage, Never>()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - CoreBluetooth Properties
    private let queue = DispatchQueue(label: "com.mcbridge.bluetooth-background-queue")
    private lazy var peripheralManager: CBPeripheralManager = {
        CBPeripheralManager(delegate: self, queue: self.queue)
    }()

    private var advertiseUUID: CBUUID { 
        CBUUID(data: EncryptionService.shared.derive(info: "McBridge_Advertise_UUID", count: 16)!)
    }
    
    private var serviceUUID: CBUUID { 
        CBUUID(data: EncryptionService.shared.derive(info: "McBridge_Service_UUID", count: 16)!)
    }

    private var characteristicUUID: CBUUID { 
        CBUUID(data: EncryptionService.shared.derive(info: "McBridge_Characteristic_UUID", count: 16)!)
    }

    // MARK: - Lifecycle
    public override init() {
        super.init()
        
        queue.async { _ = self.peripheralManager }

        sendSubject
            .receive(on: queue)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard self.power == .poweredOn else { return }
                guard !self.connections.isEmpty else { return }
                guard let char = self.textCharacteristic else { return }
                guard let data = message.toEncryptedData() else { return }

                let targetCentrals = self.connections.values
                    .filter { $0.device.isIntroduced }
                    .map { $0.central }

                guard !targetCentrals.isEmpty else {
                    Logger.bluetooth.info("No introduced devices to send message to.")
                    return
                }

                self.peripheralManager.updateValue(data, for: char, onSubscribedCentrals: targetCentrals)
                Logger.bluetooth.info("Sent an encrypted message of type \(message.type.rawValue) to \(targetCentrals.count) device(s).")
            }
            .store(in: &cancellables)
    }
    
    public func send(message: BridgerMessage) {
        sendSubject.send(message)
    }

    // MARK: - Delegate Methods
    
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let newState: BluetoothPowerState = (peripheral.state == .poweredOn) ? .poweredOn : .poweredOff
        if self.power == newState { return }
        updateState(state: &self.power, to: newState)
        Logger.bluetooth.info("Bluetooth state changed: \(self.power.rawValue)")

        if self.power == .poweredOn { setupService(); return }
        
        connections.removeAll()
        nameRequestTasks.values.forEach { $0.cancel() }
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
        guard connections[centralId] == nil else { return }
        
        let isFirstDevice = connections.isEmpty
        let newDevice = DeviceInfo(id: centralId, name: "Unknown soldier...")
        connections[centralId] = (device: newDevice, central: central)
        
        if isFirstDevice { updateState(state: &self.connection, to: .connected) }
        
        Logger.bluetooth.info("Anonymus connected: \(centralId.uuidString). Waiting for him to introduce himself.")
        
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + nameRequestTimeout)
        timer.setEventHandler { [weak self] in self?.handleDeviceTimeout(centralId)}
        nameRequestTasks[centralId] = timer
        timer.resume()
        
        reportUpdatedDeviceList()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralId = central.identifier
        if let disconnectedConnection = connections.removeValue(forKey: centralId) {
            if let timer = nameRequestTasks.removeValue(forKey: centralId) {
                timer.cancel()
            }
            
            Logger.bluetooth.info("Device \(disconnectedConnection.device.name) (\(centralId.uuidString)) has ridden off into the sunset.")

            if connections.isEmpty {
                updateState(state: &self.connection, to: .advertising)
            }
            
            reportUpdatedDeviceList()
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first else { return }
        let centralId = request.central.identifier

        guard connections[centralId] != nil else {
            Logger.bluetooth.warning("Write request from an unknown or timed-out device: \(centralId.uuidString). Rejecting.")
            peripheral.respond(to: request, withResult: .writeNotPermitted)
            return
        }
        
        guard let value = request.value else {
            peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
            return
        }
        
        handleWrite(value: value, from: centralId)
        peripheral.respond(to: request, withResult: .success)
    }
    
    // MARK: - Private Logic
    
    private func setupService() {
        guard EncryptionService.shared.isReady else {
            Logger.bluetooth.warning("Cannot setup service: Encryption not set.")
            return
        }
        
        let service = CBMutableService(type: serviceUUID, primary: true)
        self.textCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )
        service.characteristics = [self.textCharacteristic!]
        peripheralManager.add(service)
    }
    
    private func startAdvertising() {
        guard self.connection != .advertising else { return }
        guard EncryptionService.shared.isReady else {
            Logger.bluetooth.warning("Cannot start advertising: Encryption not set.")
            return
        }
        
        let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [advertiseUUID]
        ]
        
        Logger.bluetooth.info("Starting advertising...")
        Logger.bluetooth.info("  - Advertise UUID (128-bit): \(self.advertiseUUID.uuidString)")
        Logger.bluetooth.info("  - Service UUID (128-bit): \(self.serviceUUID.uuidString)")
        Logger.bluetooth.info("  - Characteristic UUID: \(self.characteristicUUID.uuidString)")
        
        peripheralManager.startAdvertising(advertisementData)
        updateState(state: &self.connection, to: .advertising)
    }
    
    private func handleWrite(value: Data, from centralID: UUID) {
        do {
            let message = try BridgerMessage.fromEncryptedData(value, address: centralID.uuidString)
            Logger.bluetooth.info("Message received & decrypted: Type \(message.type.rawValue)")
            
            switch message.type {
            case .DEVICE_NAME:
                handleDeviceNamed(id: centralID, name: message.value)
            case .CLIPBOARD:
                self.message = message
            }
        } catch {
            Logger.bluetooth.error("Error processing data from \(centralID.uuidString): \(error.localizedDescription)")
        }
    }
    
    private func handleDeviceNamed(id: UUID, name: String) {
        guard var connection = connections[id] else {
            Logger.bluetooth.warning("Attempted to name a non-existent device: \(id.uuidString).")
            return
        }
        
        connection.device.name = name
        connection.device.isIntroduced = true
        connections[id] = connection

        if let timer = nameRequestTasks.removeValue(forKey: id) {
            timer.cancel()
        }
        
        Logger.bluetooth.info("Device \(id.uuidString) has introduced itself as \(name). Nice to meet you.")
        reportUpdatedDeviceList()
    }

    private func handleDeviceTimeout(_ deviceId: UUID) {
        if let timedOutConnection = connections.removeValue(forKey: deviceId) {
            Logger.bluetooth.warning("Device \(timedOutConnection.device.name) (\(deviceId.uuidString)) timed out without introducing itself. Presumed shy.")
            if let timer = nameRequestTasks.removeValue(forKey: deviceId) {
                timer.cancel()
            }

            if connections.isEmpty {
                updateState(state: &self.connection, to: .advertising)
            }
            reportUpdatedDeviceList()
        }
    }

    private func reportUpdatedDeviceList() {
        let sortedDevices = connections.values.map(\.device).sorted { $0.name < $1.name }
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