import Foundation
import Factory
import Combine
import OSLog
import AppKit

/// AppLogic runs on background threads to handle orchestration, encryption, and transport.
public final class AppLogic {
    private let logger = Logger(subsystem: "com.mcbridger.AppLogic", category: "Broker")
    private let queue = DispatchQueue(label: "com.mcbridger.broker-queue", qos: .userInitiated)
    
    // MARK: - Subjects (Equivalent to StateFlow/SharedFlow in Kotlin)
    public let state = CurrentValueSubject<BrokerState, Never>(.idle)
    public let bluetoothPower = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOff)
    public let connectionState = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    public let devices = CurrentValueSubject<[DeviceInfo], Never>([])
    public let clipboardHistory = CurrentValueSubject<[String], Never>([])
    
    // MARK: - Services
    private var bluetoothService: BluetoothManager?
    private var clipboardService: ClipboardManager?
    
    @Injected(\.encryptionService) private var encryptionService
    @Injected(\.notificationService) private var notificationService
    
    private var cancellables = Set<AnyCancellable>()
    private var transportCancellables = Set<AnyCancellable>()

    public init() {
        logger.info("--- Broker: Initializing background instance ---")
    }

    public func bootstrap() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Bootstrapping on background queue ---")
            
            self.encryptionService.$isReady
                .sink { isReady in
                    if isReady {
                        self.logger.info("--- Broker: Security READY, setting up transport ---")
                        self.setupTransport()
                    } else {
                        self.state.send(.idle)
                    }
                }
                .store(in: &self.cancellables)
                
            self.encryptionService.bootstrap(saltHex: AppConfig.encryptionSalt)
        }
    }
    
    public func setup(mnemonic: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Manual setup initiated ---")
            self.state.send(.encrypting)
            
            self.encryptionService.setup(with: mnemonic)
                .sink { success in
                    if !success {
                        self.state.send(.error)
                        self.logger.error("--- Broker: Manual setup failed ---")
                    }
                }
                .store(in: &self.cancellables)
        }
    }
    
    public func reset() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Full reset initiated ---")
            
            self.stopTransport()
            
            self.encryptionService.reset()
                .sink { _ in
                    self.logger.info("--- Broker: Reset complete, terminating app ---")
                    DispatchQueue.main.async {
                        NSApp.terminate(nil)
                    }
                }
                .store(in: &self.cancellables)
        }
    }

    // MARK: - Internal Transport Management (Always on queue)

    private func setupTransport() {
        // 1. Clean up
        stopTransport()
        
        // 2. Create services
        let bt = Container.shared.bluetoothManager()
        let cb = Container.shared.clipboardManager()
        
        self.bluetoothService = bt
        self.clipboardService = cb
        
        // 3. Bind
        bindTransport(bt: bt, cb: cb)
        
        // 4. Start
        cb.start()
        bt.start()
        
        self.state.send(.ready)
    }

    private func stopTransport() {
        transportCancellables.removeAll()
        bluetoothService?.stop()
        clipboardService?.stop()
        bluetoothService = nil
        clipboardService = nil
        
        self.devices.send([])
        self.connectionState.send(.disconnected)
    }

    private func bindTransport(bt: BluetoothManager, cb: ClipboardManager) {
        // A. Bluetooth Power
        bt.$power
            .subscribe(on: queue)
            .sink { [weak self] p in self?.bluetoothPower.send(p) }
            .store(in: &transportCancellables)
            
        // B. Connection State -> Broker State
        bt.$connection
            .subscribe(on: queue)
            .sink { [weak self] conn in
                guard let self = self else { return }
                self.connectionState.send(conn)
                switch conn {
                case .advertising: self.state.send(.advertising)
                case .connected: self.state.send(.connected)
                case .disconnected: self.state.send(.ready)
                }
            }
            .store(in: &transportCancellables)
            
        // C. Devices
        bt.$devices
            .subscribe(on: queue)
            .sink { [weak self] d in self?.devices.send(d) }
            .store(in: &transportCancellables)

        // D. OUTGOING: Local Clipboard -> Bluetooth
        cb.$update
            .subscribe(on: queue)
            .compactMap { $0 }
            .sink { message in
                bt.send(message: message)
            }
            .store(in: &transportCancellables)

        // E. INCOMING: Bluetooth -> Local Clipboard & History
        bt.$message
            .subscribe(on: queue)
            .compactMap { $0 }
            .filter { $0.type == .CLIPBOARD }
            .sink { [weak self] message in
                guard let self = self else { return }
                
                cb.setText(message.value)
                self.addToHistory(message.value)
                
                let senderName = self.devices.value.first { $0.id.uuidString == message.address }?.name ?? "Android Device"
                self.notificationService.showNotification(
                    title: "Clipboard Synced",
                    body: "Received from \(senderName): \(message.value.prefix(50))..."
                )
            }
            .store(in: &transportCancellables)
            
        // F. Local updates to history
        cb.$update
            .subscribe(on: queue)
            .compactMap { $0 }
            .map { $0.value }
            .sink { [weak self] text in
                self?.addToHistory(text)
            }
            .store(in: &transportCancellables)
    }
    
    private func addToHistory(_ text: String) {
        var current = clipboardHistory.value
        if !current.contains(text) {
            current.insert(text, at: 0)
            if current.count > 10 {
                current.removeLast()
            }
            clipboardHistory.send(current)
        }
    }
}