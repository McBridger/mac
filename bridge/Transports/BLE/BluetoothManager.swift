import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import Combine
import Factory

public class BluetoothManager: NSObject, CBPeripheralManagerDelegate, BluetoothManaging {
    private let queue = DispatchQueue(label: "com.mcbridge.bluetooth-background-queue")
    private var _peripheralManager: CBPeripheralManager?
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "Bluetooth")
    
    // MARK: - Internal Events
    
    private enum ConnectionEvent {
        case connected(UUID)
        case introduced(UUID)
        case disconnected(UUID)
        
        var id: UUID {
            switch self {
            case .connected(let id), .introduced(let id), .disconnected(let id): return id
            }
        }
        
        var isConnected: Bool {
            if case .connected = self { return true }
            return false
        }
    }
    
    private let connectionEvents = PassthroughSubject<ConnectionEvent, Never>()
    private enum WatchdogError: Error { case timeout }

    // MARK: - Public API
    
    public let power = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOff)
    public let connection = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    public let devices = CurrentValueSubject<[DeviceInfo], Never>( [])
    public let data = PassthroughSubject<(data: Data, from: String), Never>()

    // MARK: - Private State
    
    private var advertiseUUID: CBUUID?
    private var serviceUUID: CBUUID?
    private var characteristicUUID: CBUUID?

    private var connections: [UUID: (device: DeviceInfo, central: CBCentral)] = [:]
    private var textCharacteristic: CBMutableCharacteristic?
    private let nameRequestTimeout: TimeInterval = 5.0

    private let sendSubject = PassthroughSubject<Data, Never>()
    private var cancellables = Set<AnyCancellable>()

    private var peripheralManager: CBPeripheralManager {
        if let pm = _peripheralManager { return pm }
        let pm = CBPeripheralManager(delegate: self, queue: self.queue)
        _peripheralManager = pm
        return pm
    }

    // MARK: - Initialization
    
    public override init() {
        super.init()

        // Setup watchdog
        connectionEvents
            .filter { $0.isConnected }
            .map { $0.id }
            .flatMap { [weak self, connectionEvents, queue] id in
                connectionEvents
                    .filter { $0.id == id && !$0.isConnected }
                    .first()
                    .setFailureType(to: WatchdogError.self)
                    .timeout(.seconds(self?.nameRequestTimeout ?? 5), scheduler: queue, customError: { .timeout })
                    .catch { [weak self] _ in
                        self?.handleDeviceTimeout(id)
                        return Empty<ConnectionEvent, Never>()
                    }
            }
            .sink { _ in }
            .store(in: &cancellables)

        // Setup outgoing data pipe
        sendSubject
            .receive(on: queue)
            .sink { [weak self] data in
                guard let self = self, self.power.value == .poweredOn else { return }
                
                let introducedCentrals = self.connections.values
                    .filter { $0.device.isIntroduced }
                    .map { $0.central }

                if introducedCentrals.isEmpty {
                    self.logger.warning("⚠️ Cannot send: No 'introduced' devices connected.")
                    return
                }
                
                if let char = self.textCharacteristic {
                    let success = self.peripheralManager.updateValue(data, for: char, onSubscribedCentrals: introducedCentrals)
                    if success {
                        self.logger.info("✅ Data successfully queued for \(introducedCentrals.count) device(s).")
                    } else {
                        self.logger.error("❌ Transmit queue full. Message dropped by CoreBluetooth.")
                    }
                }
            }
            .store(in: &cancellables)

        logger.info("BluetoothManager: Initialized and ready for configuration.")
    }

    // MARK: - Public API Methods
    
    public func start(advertiseUUID: CBUUID, serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        logger.info("BluetoothManager: Start requested with specific UUIDs.")
        self.advertiseUUID = advertiseUUID
        self.serviceUUID = serviceUUID
        self.characteristicUUID = characteristicUUID
        _ = peripheralManager 
    }

    public func stop() {
        logger.info("BluetoothManager: Stopping and cleaning up all state.")
        if let pm = _peripheralManager {
            pm.stopAdvertising()
            pm.removeAllServices()
            pm.delegate = nil
            _peripheralManager = nil
        }
        connections.removeAll()
        power.send(.poweredOff)
        connection.send(.disconnected)
        reportUpdatedDeviceList()
    }

    public func send(data: Data) {
        logger.debug("➡️ Queueing raw data for sending (\(data.count) bytes)")
        sendSubject.send(data)
    }

    // MARK: - CBPeripheralManagerDelegate

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let newState: BluetoothPowerState = (peripheral.state == .poweredOn) ? .poweredOn : .poweredOff
        if self.power.value == newState { return }
        self.power.send(newState)
        logger.info("Bluetooth state changed: \(newState.rawValue)")

        if self.power.value == .poweredOn {
            setupService()
        } else {
            stop()
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            logger.error("❌ Error adding service: \(error.localizedDescription)")
            return
        }
        logger.info("✅ Service added successfully. Starting advertising.")
        startAdvertising()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let id = central.identifier
        guard connections[id] == nil else { return }
        
        connections[id] = (device: DeviceInfo(id: id, name: "Connecting..."), central: central)
        if connections.count == 1 { self.connection.send(.connected) }
        
        logger.info("📱 Device connected: \(id.uuidString). Waiting for introduction.")
        connectionEvents.send(.connected(id))
        reportUpdatedDeviceList()
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let id = central.identifier
        if let conn = connections.removeValue(forKey: id) {
            logger.info("📱 Device \(conn.device.name) (\(id.uuidString)) has disconnected.")
            connectionEvents.send(.disconnected(id))
            if connections.isEmpty { self.connection.send(.advertising) }
            reportUpdatedDeviceList()
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else { return }
        let id = request.central.identifier
        
        logger.debug("⬅️ Received raw data (\(value.count) bytes) from \(id.uuidString)")
        self.data.send((data: value, from: id.uuidString))
        peripheral.respond(to: request, withResult: .success)
    }
    
    // MARK: - Internal Helpers
    
    private func setupService() {
        guard let sUUID = serviceUUID, let cUUID = characteristicUUID else {
            logger.error("❌ Cannot setup service: UUIDs missing.")
            return
        }
        
        logger.info("Setting up service: \(sUUID.uuidString)")
        let service = CBMutableService(type: sUUID, primary: true)
        self.textCharacteristic = CBMutableCharacteristic(
            type: cUUID, properties: [.read, .write, .notify], value: nil, permissions: [.readable, .writeable]
        )
        service.characteristics = [self.textCharacteristic!]
        peripheralManager.add(service)
    }
    
    private func startAdvertising() {
        guard self.connection.value != .advertising, let aUUID = advertiseUUID else { return }
        
        logger.info("Starting advertising with UUID: \(aUUID.uuidString)")
        peripheralManager.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [aUUID]])
        self.connection.send(.advertising)
    }
    
    public func markDeviceAsIntroduced(id: UUID, name: String) {
        queue.async {
            guard var conn = self.connections[id] else { return }
            conn.device.name = name
            conn.device.isIntroduced = true
            self.connections[id] = conn
            
            self.logger.info("🤝 Device \(id.uuidString) introduced as: \(name)")
            self.connectionEvents.send(.introduced(id))
            self.reportUpdatedDeviceList()
        }
    }

    private func handleDeviceTimeout(_ id: UUID) {
        if let conn = connections[id], !conn.device.isIntroduced {
            logger.warning("⏳ Device \(id.uuidString) timed out waiting for introduction. Removing.")
            connections.removeValue(forKey: id)
            if connections.isEmpty { self.connection.send(.advertising) }
            reportUpdatedDeviceList()
        }
    }

    private func reportUpdatedDeviceList() {
        let sorted = connections.values.map(\.device).sorted { $0.name < $1.name }
        logger.debug("Updating device list: \(sorted.count) devices connected.")
        self.devices.send(sorted)
    }
}