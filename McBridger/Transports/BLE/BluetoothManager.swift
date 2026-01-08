@preconcurrency import Combine
import CoreBluetooth
import Factory
import Foundation
import OSLog

public actor BluetoothManager: BluetoothManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "Bluetooth")
    
    // MARK: - Target State (The Source of Truth)
    
    private enum TargetState: Sendable {
        case idle
        case active(advertise: Data, service: Data, characteristic: Data)
    }
    
    private var targetState: TargetState = .idle
    private var isConfigured = false

    // MARK: - Public Subjects (Thread-safe via nonisolated let)
    
    nonisolated public let power = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOff)
    nonisolated public let connection = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    nonisolated public let devices = CurrentValueSubject<[DeviceInfo], Never>([])
    nonisolated public let data = PassthroughSubject<(data: Data, from: String), Never>()

    // MARK: - Private Hardware State
    
    private var peripheral: CBPeripheralManager?
    private var proxy: BluetoothDelegate?
    private var textCharacteristic: CBMutableCharacteristic?
    
    private let cbQueue = DispatchQueue(label: "com.mcbridger.ble-queue", qos: .userInitiated)
    private var connections: [UUID: (device: DeviceInfo, central: CBCentral)] = [:]
    private var introductionTasks: [UUID: Task<Void, Never>] = [:]
    private let nameRequestTimeout: TimeInterval

    // MARK: - Initialization

    public init(nameRequestTimeout: TimeInterval = 5.0) {
        self.nameRequestTimeout = nameRequestTimeout
        logger.info("BluetoothManager: Initialized in Actor mode.")
    }

    private func getPeripheralManager() -> CBPeripheralManager {
        if let pm = peripheral { return pm }
        
        let delegate = BluetoothDelegate(actor: self)
        self.proxy = delegate
        
        let pm = CBPeripheralManager(delegate: delegate, queue: cbQueue)
        self.peripheral = pm
        return pm
    }

    // MARK: - Public API (BluetoothManaging)

    public func start(advertise: Data, service: Data, characteristic: Data) {
        logger.info("➡️ BluetoothManager: Start requested. Moving to ACTIVE state.")
        targetState = .active(
            advertise: advertise,
            service: service,
            characteristic: characteristic
        )
        refreshHardwareState()
    }

    public func stop() {
        logger.info("⏹️ BluetoothManager: Stop requested. Moving to IDLE state.")
        targetState = .idle
        
        peripheral?.stopAdvertising()
        peripheral?.removeAllServices()
        
        isConfigured = false
        handlePowerLost()
    }

    public func send(data: Data) {
        guard power.value == .poweredOn else { 
            logger.warning("⚠️ Dropping data: Bluetooth is OFF.")
            return 
        }

        let introducedCentrals = connections.values
            .filter { $0.device.isIntroduced }
            .map { $0.central }

        guard !introducedCentrals.isEmpty else {
            logger.warning("⚠️ Cannot send: No 'introduced' devices connected.")
            return
        }

        guard let char = textCharacteristic else { return }
        
        let success = getPeripheralManager().updateValue(data, for: char, onSubscribedCentrals: introducedCentrals)
        if success { logger.info("✅ Data successfully queued for \(introducedCentrals.count) device(s).") }
        else { logger.error("❌ Transmit queue full. Message dropped.") }
    }

    public func markDeviceAsIntroduced(id: UUID, name: String) {
        guard var conn = connections[id] else { return }
        introductionTasks.removeValue(forKey: id)?.cancel()
        
        conn.device.name = name
        conn.device.isIntroduced = true
        connections[id] = conn

        logger.info("🤝 Device \(id.uuidString) introduced as: \(name)")
        reportUpdatedDeviceList()
    }

    // MARK: - Internal Hardware Orchestration

    private func refreshHardwareState() {
        let state = getPeripheralManager().state
        
        switch state {
        case .poweredOn:
            power.send(.poweredOn)
            applyActiveConfig()
        case .poweredOff:
            power.send(.poweredOff)
            handlePowerLost()
        case .resetting: logger.info("Bluetooth hardware is resetting...")
        case .unauthorized: logger.error("Bluetooth permission denied.")
        case .unsupported: logger.error("Bluetooth LE is not supported on this Mac.")
        default: break
        }
    }

    private func applyActiveConfig() {
        guard case let .active(_, svcData, chrData) = targetState else { return }
        
        guard !isConfigured else {
            startAdvertising()
            return
        }

        logger.info("🛠️ Configuring Bluetooth services...")
        let svcUUID = CBUUID(data: svcData)
        let chrUUID = CBUUID(data: chrData)
        
        let service = CBMutableService(type: svcUUID, primary: true)
        let characteristic = CBMutableCharacteristic(
            type: chrUUID, properties: [.read, .write, .notify], value: nil,
            permissions: [.readable, .writeable]
        )
        service.characteristics = [characteristic]
        textCharacteristic = characteristic
        
        let pm = getPeripheralManager()
        pm.removeAllServices()
        pm.add(service)
        isConfigured = true
    }

    private func startAdvertising() {
        guard case let .active(advData, _, _) = targetState else { return }
        let pm = getPeripheralManager()
        guard !pm.isAdvertising else { return }
        
        let advUUID = CBUUID(data: advData)
        logger.info("📢 Starting advertising with UUID: \(advUUID.uuidString)")
        pm.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [advUUID]])
        connection.send(.advertising)
    }

    private func handlePowerLost() {
        connections.removeAll()
        if connection.value != .disconnected { connection.send(.disconnected) }
        reportUpdatedDeviceList()
    }

    // MARK: - Internal Handlers (called by Proxy)

    func handleHardwareStateChange(_ state: CBManagerState) {
        logger.info("Hardware state changed: \(state.rawValue)")
        refreshHardwareState()
    }

    func handleServiceAdded(_ service: CBService, error: Error?) {
        if let error {
            logger.error("❌ Error adding service: \(error.localizedDescription)")
            isConfigured = false
            return
        }
        logger.info("✅ Service added successfully.")
        startAdvertising()
    }

    func handleCentralSubscribed(_ central: CBCentral, characteristic: CBCharacteristic) {
        let id = central.identifier
        guard connections[id] == nil else { return }

        connections[id] = (device: DeviceInfo(id: id, name: "Connecting..."), central: central)
        updateConnectionState()

        logger.info("📱 Device connected: \(id.uuidString). Waiting for introduction.")
        
        introductionTasks[id] = Task {
            try? await Task.sleep(nanoseconds: UInt64(nameRequestTimeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            self.checkDeviceIntroductionTimeout(id)
        }
        
        reportUpdatedDeviceList()
    }

    func handleCentralUnsubscribed(_ central: CBCentral, characteristic: CBCharacteristic) {
        let id = central.identifier
        introductionTasks.removeValue(forKey: id)?.cancel()
        
        guard let conn = connections.removeValue(forKey: id) else { return }
        logger.info("📱 Device \(conn.device.name) (\(id.uuidString)) has disconnected.")
        updateConnectionState()
        reportUpdatedDeviceList()
    }

    func handleReceiveWrite(_ requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else { return }
        let id = request.central.identifier

        logger.debug("⬅️ Received raw data (\(value.count) bytes) from \(id.uuidString)")
        data.send((data: value, from: id.uuidString))
        getPeripheralManager().respond(to: request, withResult: .success)
    }

    private func checkDeviceIntroductionTimeout(_ id: UUID) {
        guard let conn = connections[id], !conn.device.isIntroduced else { return }
        logger.warning("⏳ Device \(id.uuidString) timed out waiting for introduction. Removing.")
        connections.removeValue(forKey: id)
        updateConnectionState()
        reportUpdatedDeviceList()
    }

    private func updateConnectionState() {
        guard connections.isEmpty else {
            if connection.value != .connected { connection.send(.connected) }
            return
        }

        if power.value == .poweredOn, case .active = targetState {
            if connection.value != .advertising { connection.send(.advertising) }
            return
        }
        
        if connection.value != .disconnected { connection.send(.disconnected) }
    }

    private func reportUpdatedDeviceList() {
        let sorted = connections.values.map(\.device).sorted { $0.name < $1.name }
        devices.send(sorted)
    }
}
