import Foundation
import Factory
import Combine
import OSLog
import AppKit
import CoreBluetooth

/// AppLogic (Broker) runs on background threads to handle orchestration, encryption, and transport.
public final class AppLogic {
    private let logger = Logger(subsystem: "com.mcbridger.AppLogic", category: "Broker")
    private let queue = DispatchQueue(label: "com.mcbridger.broker-queue", qos: .userInitiated)
    
    // MARK: - Subjects
    public let state = CurrentValueSubject<BrokerState, Never>(.idle)
    public let clipboardHistory = CurrentValueSubject<[String], Never>([])
    
    // MARK: - Services
    @Injected(\.clipboardManager) private var clipboardService: ClipboardManaging
    @Injected(\.encryptionService) private var encryptionService: EncryptionServing
    @Injected(\.notificationService) private var notificationService
    @Injected(\.bluetoothManager) private var bluetoothService: BluetoothManaging
    
    private var cancellables = Set<AnyCancellable>()

    public init() {
        logger.info("--- Broker: Initializing background instance ---")
    }

    public func bootstrap() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Bootstrapping on background queue ---")
            
            // 1. Outgoing: Clipboard -> Encrypt -> Transport
            self.clipboardService.update
                .subscribe(on: self.queue)
                .compactMap { $0 }
                .sink { [weak self] message in
                    self?.addToHistory(message.value)
                    self?.sendToTransport(message)
                }
                .store(in: &self.cancellables)
            
            // 2. Lifecycle: Encryption Ready -> Setup Transport
            self.encryptionService.isReady
                .receive(on: self.queue)
                .sink { [weak self] isReady in
                    if isReady {
                        self?.logger.info("--- Broker: Security READY, setting up transport ---")
                        self?.setupTransport()
                    } else {
                        self?.state.send(.idle)
                    }
                }
                .store(in: &self.cancellables)

            // 3. Incoming Pipeline: Raw Bluetooth -> Decrypted Messages (Shared)
            let incomingMessages = self.bluetoothService.data
                .subscribe(on: self.queue)
                .compactMap { $0 }
                .flatMap(maxPublishers: .max(1)) { [weak self] (data, address) in
                    Just((data, address))
                        .tryMap { d, a in try self?.encryptionService.decryptMessage(d, address: a) }
                        .compactMap { $0 }
                        .catch { [weak self] error in
                            self?.logger.error("--- Broker: Decryption error: \(error.localizedDescription) ---")
                            return Empty<BridgerMessage, Never>()
                        }
                }
                .share()

            // Branch A: Clipboard Updates
            incomingMessages
                .filter { $0.type == .CLIPBOARD }
                .sink { [weak self] message in
                    self?.logger.info("--- Broker: Handling Incoming Clipboard ---")
                    self?.clipboardService.setText(message.value)
                    self?.addToHistory(message.value)
                    self?.notificationService.showNotification(
                        title: "Clipboard Synced",
                        body: "New data received via McBridger"
                    )
                }
                .store(in: &self.cancellables)

            // Branch B: Device Introduction
            incomingMessages
                .filter { $0.type == .DEVICE_NAME }
                .sink { [weak self] message in
                    self?.logger.info("--- Broker: Handling Device Introduction: \(message.value) ---")
                    if let address = message.address, let uuid = UUID(uuidString: address) {
                        self?.bluetoothService.markDeviceAsIntroduced(id: uuid, name: message.value)
                    }
                }
                .store(in: &self.cancellables)
        }
    }
    
    public func setup(mnemonic: String) {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Manual setup initiated ---")
            self.state.send(.encrypting)
            self.encryptionService.setup(with: mnemonic)
        }
    }
    
    public func reset() {
        queue.async { [weak self] in
            guard let self = self else { return }
            self.logger.info("--- Broker: Full reset initiated ---")
            self.bluetoothService.stop()
            self.encryptionService.reset()
            self.logger.info("--- Broker: Reset complete, returning to IDLE state ---")
        }
    }

    // MARK: - Internal Orchestration

    private func setupTransport() {
        self.state.send(.transportInitializing)
        
        guard let advID = encryptionService.derive(info: "McBridge_Advertise_UUID", count: 16),
              let svcID = encryptionService.derive(info: "McBridge_Service_UUID", count: 16),
              let chrID = encryptionService.derive(info: "McBridge_Characteristic_UUID", count: 16) else {
            self.logger.error("--- Broker: Failed to derive transport UUIDs ---")
            self.state.send(.error)
            return
        }
        
        bluetoothService.start(
            advertiseUUID: CBUUID(data: advID),
            serviceUUID: CBUUID(data: svcID),
            characteristicUUID: CBUUID(data: chrID)
        )
        
        self.state.send(.ready)
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name("com.mcbridger.service.ready"),
            object: nil,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    private func sendToTransport(_ message: BridgerMessage) {
        guard let data = encryptionService.encryptMessage(message) else {
            logger.error("--- Broker: Encryption failed for outgoing message ---")
            return
        }
        bluetoothService.send(data: data)
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
