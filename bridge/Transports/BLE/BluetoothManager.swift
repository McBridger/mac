import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import Combine
import Factory

public class BluetoothManager: NSObject, CBPeripheralManagerDelegate {
    @Injected(\.encryptionService) private var encryptionService

    @UseState public private(set) var power: BluetoothPowerState = .poweredOff
    @UseState public private(set) var connection: ConnectionState = .disconnected
    @UseState public private(set) var devices: [DeviceInfo] = []
    @Event public private(set) var message: BridgerMessage?

    private var connections: [UUID: (device: DeviceInfo, central: CBCentral)] = [:]
    private var textCharacteristic: CBMutableCharacteristic?
    private var nameRequestTasks: [UUID: DispatchSourceTimer] = [:]
    private let nameRequestTimeout: TimeInterval = 5.0

    private let sendSubject = PassthroughSubject<BridgerMessage, Never>()
    private var cancellables = Set<AnyCancellable>()

    private let queue = DispatchQueue(label: "com.mcbridge.bluetooth-background-queue")
    private var _peripheralManager: CBPeripheralManager?

    private var peripheralManager: CBPeripheralManager {
        if let pm = _peripheralManager { return pm }
        let pm = CBPeripheralManager(delegate: self, queue: self.queue)
        _peripheralManager = pm
        return pm
    }

    private var advertiseUUID: CBUUID { 
        CBUUID(data: encryptionService.derive(info: "McBridge_Advertise_UUID", count: 16) ?? Data())
    }
    
    private var serviceUUID: CBUUID { 
        CBUUID(data: encryptionService.derive(info: "McBridge_Service_UUID", count: 16) ?? Data())
    }

    private var characteristicUUID: CBUUID { 
        CBUUID(data: encryptionService.derive(info: "McBridge_Characteristic_UUID", count: 16) ?? Data())
    }

    public override init() {
        super.init()
        
        sendSubject
            .receive(on: queue)
            .sink { [weak self] message in
                guard let self = self else { return }
                guard self.power == .poweredOn else {
                    Logger.bluetooth.error("❌ Cannot send: Bluetooth is OFF")
                    return
                }
                
                if self.connections.isEmpty {
                    Logger.bluetooth.warning("⚠️ Cannot send: No devices connected")
                    return
                }

                guard let char = self.textCharacteristic else {
                    Logger.bluetooth.error("❌ Cannot send: Characteristic not initialized")
                    return
                }
                
                guard let data = self.encryptionService.encryptMessage(message) else {
                    Logger.bluetooth.error("❌ Cannot send: Encryption failed")
                    return
                }

                let introducedDevices = self.connections.values.filter { $0.device.isIntroduced }
                let targetCentrals = introducedDevices.map { $0.central }

                if targetCentrals.isEmpty {
                    Logger.bluetooth.warning("⚠️ No 'introduced' devices found. Total connected: \(self.connections.count).")
                    for (id, conn) in self.connections {
                        Logger.bluetooth.debug("   - Connected device: \(conn.device.name) (ID: \(id), Introduced: \(conn.device.isIntroduced))")
                    }
                    return
                }

                let success = self.peripheralManager.updateValue(data, for: char, onSubscribedCentrals: targetCentrals)
                
                if success {
                    Logger.bluetooth.info("✅ Successfully queued encrypted message for \(targetCentrals.count) device(s).")
                } else {
                    Logger.bluetooth.error("❌ Local transmit queue is full. Message dropped by CoreBluetooth.")
                }
            }
            .store(in: &cancellables)
    }
    
    public func start() {
        Logger.bluetooth.info("BluetoothManager: Explicit start requested.")
        _ = peripheralManager // Triggers lazy creation of CBPeripheralManager
    }

    public func stop() {
        Logger.bluetooth.info("BluetoothManager: Stopping and cleaning up.")
        if let pm = _peripheralManager {
            pm.stopAdvertising()
            pm.removeAllServices()
            pm.delegate = nil
            _peripheralManager = nil
        }
        connections.removeAll()
        nameRequestTasks.values.forEach { $0.cancel() }
        nameRequestTasks.removeAll()
        updateState(state: &self.power, to: .poweredOff)
        updateState(state: &self.connection, to: .disconnected)
        reportUpdatedDeviceList()
    }

    public func send(message: BridgerMessage) {
        Logger.bluetooth.debug("➡️ Attempting to send message of type \(message.type.rawValue)")
        sendSubject.send(message)
    }

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
    
    private func setupService() {
        guard encryptionService.isReady else {
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
        guard encryptionService.isReady else {
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
            let message = try self.encryptionService.decryptMessage(value, address: centralID.uuidString)
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