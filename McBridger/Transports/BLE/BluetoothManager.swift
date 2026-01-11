@preconcurrency import Combine
import CoreBluetooth
import Factory
import Foundation
import OSLog

public actor BluetoothManager: BluetoothManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "Bluetooth")
    
    @Injected(\.bleDriver) private var driver: BLEDriverProtocol
    
    // --- 1. PUBLIC PIPES (UI Read-only) ---
    nonisolated public let power = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOff)
    nonisolated public let connection = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    nonisolated public let devices = CurrentValueSubject<[DeviceInfo], Never>([])
    nonisolated public let data = PassthroughSubject<(data: Data, from: String), Never>()

    // --- 2. PRIVATE STATE ---
    private struct State: Equatable {
        var isPoweredOn: Bool = false
        var isAdvertising: Bool = false
        var connections: [UUID: DeviceInfo] = [:]
    }

    private var state = State()
    private var introductionTasks: [UUID: Task<Void, Never>] = [:]
    private let nameRequestTimeout: TimeInterval

    // --- 3. LIFECYCLE ---
    public init(nameRequestTimeout: TimeInterval = 5.0) {
        self.nameRequestTimeout = nameRequestTimeout
        logger.info("BluetoothManager: Initialized with Clean State Machine.")
        
        Task { [weak self] in
            guard let self else { return }
            for await event in await self.driver.eventStream {
                await self.process(event)
            }
        }
    }

    // --- 4. PUBLIC API ---
    public func start(advertise: Data, service: Data, characteristic: Data) {
        logger.info("➡️ BluetoothManager: Start requested.")
        let config = BLEConfig(
            advertise: advertise,
            service: service,
            characteristic: characteristic
        )
        driver.advertise(config)
    }

    public func stop() {
        logger.info("⏹️ BluetoothManager: Stop requested.")
        driver.stop()
        
        resetRuntime()
        setState { $0 = State() }
    }

    public func send(data: Data) {
        guard state.isPoweredOn else { 
            logger.warning("⚠️ Dropping data: Bluetooth is OFF.")
            return 
        }

        let introducedIds = state.connections.values
            .filter { $0.isIntroduced }
            .map { $0.id }

        guard !introducedIds.isEmpty else {
            logger.warning("⚠️ Cannot send: No 'introduced' devices connected.")
            return
        }

        let success = driver.send(data, to: introducedIds)
        if !success { logger.error("❌ Transmit failed.") }
    }

    public func markDeviceAsIntroduced(id: UUID, name: String) {
        setState {
            guard var device = $0.connections[id] else { return }
            introductionTasks.removeValue(forKey: id)?.cancel()
            
            device.name = name
            device.isIntroduced = true
            $0.connections[id] = device
            logger.info("🤝 Device \(id.uuidString) introduced as: \(name)")
        }
    }

    // --- 5. EVENT HANDLER (State Mutation) ---
    private func process(_ event: BLEDriverEvent) {
        switch event {
        case .didUpdateState(let status):
            let isNowOn = (status == .poweredOn)
            logger.info("Hardware state: \(String(describing: status))")
            
            if state.isPoweredOn && !isNowOn {
                resetRuntime()
                setState { $0 = State() }
            } else {
                setState { $0.isPoweredOn = isNowOn }
            }
            
        case .isAdvertising(let isActive):
            setState { $0.isAdvertising = isActive }
            logger.info("Advertising status: \(isActive)")
            
        case .didSubscribe(let id):
            handleNewSubscription(id)
            
        case .didUnsubscribe(let id):
            handleUnsubscription(id)
            
        case .didReceiveData(let rawData, let fromId):
            data.send((data: rawData, from: fromId.uuidString))
            return 
            
        case .didAddService(let error):
            if let error {
                logger.error("❌ Failed to add service: \(error.localizedDescription)")
            } else {
                logger.info("✅ Service added successfully.")
            }
            return
            
        case .isReadyToResend:
            logger.debug("Driver ready for more data.")
            return
        }
    }

    private func handleNewSubscription(_ id: UUID) {
        setState {
            guard $0.connections[id] == nil else { return }
            $0.connections[id] = DeviceInfo(id: id, name: "Connecting...")
            logger.info("📱 Device connected: \(id.uuidString). Waiting for introduction.")
            
            introductionTasks[id] = Task {
                try? await Task.sleep(nanoseconds: UInt64(nameRequestTimeout * 1_000_000_000))
                guard !Task.isCancelled else { return }
                self.handleIntroductionTimeout(id)
            }
        }
    }

    private func handleUnsubscription(_ id: UUID) {
        introductionTasks.removeValue(forKey: id)?.cancel()
        setState {
            if let device = $0.connections.removeValue(forKey: id) {
                logger.info("📱 Device \(device.name) (\(id.uuidString)) disconnected.")
            }
        }
    }

    private func handleIntroductionTimeout(_ id: UUID) {
        setState {
            guard let device = $0.connections[id], !device.isIntroduced else { return }
            logger.warning("⏳ Device \(id.uuidString) introduction timeout. Removing.")
            $0.connections.removeValue(forKey: id)
        }
    }

    private func resetRuntime() {
        introductionTasks.values.forEach { $0.cancel() }
        introductionTasks.removeAll()
    }

    private func setState(_ mutation: (inout State) -> Void) {
        mutation(&state)
        broadcast()
    }

    // --- 6. STATE PROJECTION ---
    private func broadcast() {
        // 1. Power
        let newPower = state.isPoweredOn ? BluetoothPowerState.poweredOn : .poweredOff
        if power.value != newPower { power.send(newPower) }
        
        // 2. Connection State
        let newConn: ConnectionState
        if !state.isPoweredOn {
            newConn = .disconnected
        } else if !state.connections.isEmpty {
            newConn = .connected
        } else if state.isAdvertising {
            newConn = .advertising
        } else {
            newConn = .disconnected
        }
        if connection.value != newConn { connection.send(newConn) }
        
        // 3. Devices
        let sortedDevices = state.connections.values.sorted { $0.name < $1.name }
        if devices.value != sortedDevices {
            devices.send(sortedDevices)
        }
    }
}