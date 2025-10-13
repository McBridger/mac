import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import CoreModels

// NOT @MainActor. Just an actor. Its own world.
public actor BluetoothManager {
    // All state is now protected by the actor. No races.
    private var _powerState: BluetoothPowerState = .poweredOff
    private var _connectionState: ConnectionState = .disconnected
    private var devices: [UUID: DeviceInfo] = [:]
    private var activeTasks: Set<Task<Void, Never>> = []

    // MARK: - Public Streams

    public nonisolated var powerState: AsyncStream<BluetoothPowerState> {
        powerStateStream
    }
    public nonisolated var connectionState: AsyncStream<ConnectionState> {
        connectionStateStream
    }
    public nonisolated var deviceList: AsyncStream<[DeviceInfo]> {
        deviceListStream
    }
    public nonisolated var messages: AsyncStream<BridgerMessage> {
        messageStream
    }

    fileprivate let powerStateStream: AsyncStream<BluetoothPowerState>
    fileprivate let connectionStateStream: AsyncStream<ConnectionState>
    fileprivate let deviceListStream: AsyncStream<[DeviceInfo]>
    fileprivate let messageStream: AsyncStream<BridgerMessage>
    private let powerStateContinuation: AsyncStream<BluetoothPowerState>.Continuation
    private let connectionStateContinuation: AsyncStream<ConnectionState>.Continuation
    private let deviceListContinuation: AsyncStream<[DeviceInfo]>.Continuation
    private let messageContinuation: AsyncStream<BridgerMessage>.Continuation

    private var textCharacteristic: CBMutableCharacteristic?

    // Reference to our "Talking Door"
    private lazy var delegateProxy: CBPeripheralDelegateProxy = {
        CBPeripheralDelegateProxy(actor: self)
    }()

    private lazy var peripheralManager: CBPeripheralManager = {
        let queue = DispatchQueue(label: "com.mcbridge.bluetooth-background-queue")
        return CBPeripheralManager(delegate: self.delegateProxy, queue: queue)
    }()

    private let advertiseUUID = CBUUID(string: "fdd2")
    private let bridgerServiceUUID = CBUUID(string: "ccfa23b4-ba6f-448a-827d-c25416ec432e")
    private let characteristicUUID = CBUUID(string: "315eca9d-0dbc-498d-bb4d-1d59d7c5bc3b")

    private var nameRequestTasks: [UUID: Task<Void, Never>] = [:]
    private let nameRequestTimeout: TimeInterval = 5.0
    private var reportingTask: Task<Void, Never>?

    // MARK: - Lifecycle

    private init() {
        (powerStateStream, powerStateContinuation) = AsyncStream.makeStream()
        (connectionStateStream, connectionStateContinuation) = AsyncStream.makeStream()
        (deviceListStream, deviceListContinuation) = AsyncStream.makeStream()
        (messageStream, messageContinuation) = AsyncStream.makeStream()
    }

    public static func create() async -> BluetoothManager {
        let manager = BluetoothManager()
        await manager.activate()
        return manager
    }

    private func activate() {
        // Accessing the lazy var triggers its initialization within the actor's context.
        _ = self.peripheralManager
    }

    public func send(message: BridgerMessage) {
        guard let data = try? message.toData() else {
            Logger.bluetooth.error("Could not encode message to data. Some garbage.")
            return
        }
        
        if _powerState == .poweredOn, let characteristic = textCharacteristic, !devices.isEmpty {
            peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
            Logger.bluetooth.info("Sent a message of type \(message.type.rawValue) by command.")
        }
    }

    // This method will be CALLED by the proxy delegate.
    // It is already running on the actor's queue.
    func handleStateUpdate(to bleState: CBManagerState) async {
        let newState: BluetoothPowerState = (bleState == .poweredOn) ? .poweredOn : .poweredOff
        guard self._powerState != newState else { return }
        
        self._powerState = newState
        Logger.bluetooth.info("Bluetooth state changed: \(newState.rawValue)")
        
        powerStateContinuation.yield(newState)
        
        if newState == .poweredOn {
            setupService()
        } else {
            devices.removeAll()
            await updateConnectionState(to: .disconnected)
            await reportUpdatedDeviceList() // Here without debounce, immediately
        }
    }

    private func updateConnectionState(to newState: ConnectionState) async {
        guard self._connectionState != newState else { return }
        self._connectionState = newState
        connectionStateContinuation.yield(newState)
    }

    private func setupService() {
        // ... code unchanged ...
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

    func startAdvertising(error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Error adding service: \(error.localizedDescription)")
            return
        }
        
        guard _connectionState != .advertising else { return }
        
        let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "McBridge"
        let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [advertiseUUID],
          CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        Task {
            await updateConnectionState(to: .advertising) // <-- Update via new method
        }
        Logger.bluetooth.info("Started yelling on the air with the handle \(deviceName).")
    }

    func handleSubscription(from centralId: UUID) {
        guard devices[centralId] == nil else { return }
        
        let newDevice = DeviceInfo(id: centralId, name: "Unknown soldier...")
        devices[centralId] = newDevice
        Task {
            await updateConnectionState(to: .connected) // <-- Update via new method
        }
        
        Logger.bluetooth.info("Anonymus connected: \(centralId.uuidString). Waiting for him to introduce himself.")
        
        nameRequestTasks[centralId] = Task {
            do {
                try await Task.sleep(for: .seconds(nameRequestTimeout))
                await handleDeviceTimeout(centralId)
            } catch {}
        }
        
        Task {
            await reportUpdatedDeviceListDebounced()
        }
    }

    func handleUnsubscription(from centralId: UUID) {
        if let disconnectedDevice = devices.removeValue(forKey: centralId) {
            nameRequestTasks[centralId]?.cancel()
            nameRequestTasks.removeValue(forKey: centralId)
            
            Logger.bluetooth.info("Device \(disconnectedDevice.name) (\(centralId.uuidString)) has ridden off into the sunset.")

            if devices.isEmpty {
                Task {
                    await updateConnectionState(to: .advertising) // <-- Back to advertising
                }
            }
            
            Task {
                await reportUpdatedDeviceListDebounced()
            }
        }
    }

    func handleWrite(value: Data, from centralID: UUID) async {
        // ... as before, only now RemoteMessageReceived is posted to the outside world
        do {
            let message = try BridgerMessage.fromData(value, address: centralID.uuidString)
            Logger.bluetooth.info("Message decrypted: Type \(message.type.rawValue), value: '\(message.value)'")
            
            switch message.type {
            case .DEVICE_NAME:
                await handleDeviceNamed(id: centralID, name: message.value)
            case .CLIPBOARD:
                messageContinuation.yield(message)
            }
        } catch {
            Logger.bluetooth.error("Error decoding data from \(centralID.uuidString): \(error.localizedDescription)")
        }
    }

    private func handleDeviceNamed(id: UUID, name: String) async {
        devices[id]?.name = name
        nameRequestTasks[id]?.cancel()
        nameRequestTasks.removeValue(forKey: id)
        Logger.bluetooth.info("Device \(id.uuidString) has introduced itself as \(name). Nice to meet you.")
        await reportUpdatedDeviceListDebounced()
    }

    private func handleDeviceTimeout(_ deviceId: UUID) async {
        if let timedOutDevice = devices[deviceId], timedOutDevice.name == "Unknown soldier..." {
            Logger.bluetooth.warning("Device \(deviceId.uuidString) timed out without introducing itself. Presumed shy.")
        }
        nameRequestTasks.removeValue(forKey: deviceId)
    }

    // Instead of updating a publisher - a direct post to the bus
    private func reportUpdatedDeviceList() async {
        let sortedDevices = Array(devices.values).sorted { $0.name < $1.name }
        deviceListContinuation.yield(sortedDevices)
        Logger.bluetooth.debug("Sending updated device list: \(sortedDevices.count) devices")
    }

    private func reportUpdatedDeviceListDebounced() async {
        reportingTask?.cancel()
        
        reportingTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
                await reportUpdatedDeviceList()
            } catch {}
        }
    }

}

// This class is a bridge between the old world (CoreBluetooth) and the new (Actors).
// It has no state of its own. It's just a transmitter.
// We mark it as `@unchecked Sendable` because it only holds a weak reference
// to the actor and has no other state. We are responsible for its safety.
private final class CBPeripheralDelegateProxy: NSObject, CBPeripheralManagerDelegate {
    // Weak reference to the owner to avoid a cycle.
    private weak var owner: BluetoothManager?

    init(actor: BluetoothManager) {
        self.owner = actor
    }

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let state = peripheral.state // Extract Sendable data
        Task { [weak owner] in
            await owner?.handleStateUpdate(to: state)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { [weak owner] in
            await owner?.startAdvertising(error: error)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let centralID = central.identifier // Extract Sendable data
        Task { [weak owner] in
            await owner?.handleSubscription(from: centralID)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralID = central.identifier // Extract Sendable data
        Task { [weak owner] in
            await owner?.handleUnsubscription(from: centralID)
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else { return }
        let centralID = request.central.identifier // Extract Sendable data
        
        Task { [weak owner] in
            await owner?.handleWrite(value: value, from: centralID)
        }
        // This must be called on the same queue as the delegate method, outside the async Task.
        peripheral.respond(to: request, withResult: .success)
    }
}

// Convenient extension for the logger, as it was
extension Logger {
private static let subsystem = Bundle.main.bundleIdentifier!
static let bluetooth = Logger(subsystem: subsystem, category: "BluetoothManager")
}

extension Task where Failure == Never {
    func store(in set: inout Set<Task<Void, Never>>) {
        set.insert(self as! Task<Void, Never>)
    }
}
