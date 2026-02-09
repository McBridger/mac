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
    @Injected(\.tcpManager) private var tcpService: TcpManaging
    @Injected(\.blobStorageManager) private var blobStorageService: BlobStorageManaging
    
    private var cancellables = Set<AnyCancellable>()
    private var partnerTcpTarget: (ip: String, port: Int)?

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
                .sink { [weak self] message in self?.onLocalUpdate(message) }
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

            // 3. Incoming Pipeline: Bluetooth & TCP -> Decoded Messages
            let bluetoothMessages = self.bluetoothService.data
                .subscribe(on: self.queue)
                .compactMap { $0 }
                .flatMap(maxPublishers: .max(1)) { [weak self] (data, address) in
                    self?.decrypt(data: data, address: address) ?? Empty().eraseToAnyPublisher()
                }
            
            let tcpMessages = self.tcpService.messages
                .subscribe(on: self.queue)
            
            Publishers.Merge(bluetoothMessages, tcpMessages)
                .receive(on: self.queue)
                .sink { [weak self] message in self?.onIncomingUpdate(message) }
                .store(in: &self.cancellables)

            // 4. Blob assembly completion -> Clipboard
            NotificationCenter.default.publisher(for: .blobDownloadComplete)
                .subscribe(on: self.queue)
                .sink { [weak self] note in
                    guard let url = note.userInfo?["path"] as? URL else { return }
                    self?.logger.info("--- Broker: Blob assembly COMPLETE. Copying to clipboard: \(url.lastPathComponent) ---")
                    self?.clipboardService.setFile(url: url)
                    self?.notificationService.showNotification(
                        title: "File Received",
                        body: "\(url.lastPathComponent) copied to clipboard"
                    )
                }
                .store(in: &self.cancellables)
        }
    }
    
    private func decrypt(data: Data, address: String?) -> AnyPublisher<BridgerMessage, Never> {
        Just((data, address))
            .tryMap { [weak self] d, a in
                try self?.encryptionService.decryptMessage(d, address: a)
            }
            .compactMap { $0 }
            .catch { [weak self] error -> Empty<BridgerMessage, Never> in
                self?.logger.error("--- Broker: Decryption error: \(error.localizedDescription) ---")
                return Empty()
            }
            .eraseToAnyPublisher()
    }

    private func onIncomingUpdate(_ message: BridgerMessage) {
        switch message.content {
            case .tiny(let text):
                self.logger.info("--- Broker: Handling Incoming Tiny Message ---")
                self.clipboardService.setText(text)
                self.addToHistory(text)
                self.notificationService.showNotification(
                    title: "Message Synced",
                    body: "New data received via McBridger"
                )
            
            case .intro(let deviceName, let ip, let port):
                self.logger.info("--- Broker: Handling Device Introduction: \(deviceName) at \(ip):\(port) ---")
                self.partnerTcpTarget = (ip, port)
                if let address = message.address, let uuid = UUID(uuidString: address) {
                    Task { [weak self] in
                        await self?.bluetoothService.markDeviceAsIntroduced(id: uuid, name: deviceName)
                    }
                }
                
                // Proactively send our own intro back if we haven't yet
                self.sendIntro()

            case .blob(let name, let size, let blobType):
                self.logger.info("--- Broker: Incoming Blob: \(name); Size: \(size); Type: \(blobType.rawValue) ---")
                Task { [weak self] in
                    await self?.blobStorageService.registerBlob(id: message.id, name: name, size: size, type: blobType)
                }
                
            case .chunk(let id, let offset, let data):
                Task { [weak self] in
                    await self?.blobStorageService.handleChunk(id: id, offset: offset, data: data)
                }
        }
    }

    private func onLocalUpdate(_ message: BridgerMessage) {
        switch message.content {
            case .tiny(let text):
                self.addToHistory(text)
                self.sendToTransport(message)

            case .blob(let name, let size, let blobType):
                self.logger.info("--- Broker: Outgoing Blob from Clipboard: \(name); Size: \(size) ---")
                
                // 1. Send announcement to transport (BT/Notification)
                self.sendToTransport(message)
                
                // 2. If we have a TCP target and this is a local file (indicated by 'address' being a URL)
                if let target = partnerTcpTarget, 
                   let urlString = message.address,
                   let fileURL = URL(string: urlString) {
                    self.logger.info("--- Broker: Starting TCP stream for \(name) to \(target.ip):\(target.port) ---")
                    Task { [weak self] in
                        do {
                            try await self?.tcpService.sendBlob(message, url: fileURL, to: target.ip, port: target.port)
                        } catch {
                            self?.logger.error("--- Broker: Failed to stream outbound blob: \(error.localizedDescription) ---")
                        }
                    }
                } else {
                    self.logger.warning("--- Broker: Nowhere to stream blob \(name) (no target or local URL) ---")
                }

            default: 
                self.sendToTransport(message)
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
            Task { [weak self] in
                await self?.bluetoothService.stop()
            }
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
        
        Task { [weak self, advID, svcID, chrID] in
            await self?.bluetoothService.start(
                advertise: advID,
                service: svcID,
                characteristic: chrID
            )
            self?.state.send(.ready)
            DistributedNotificationCenter.default().postNotificationName(
                NSNotification.Name("com.mcbridger.service.ready"),
                object: nil,
                userInfo: nil,
                deliverImmediately: true
            )
        }
        
        Task { [weak self] in
            do {
                try await self?.tcpService.start(port: 41492)
                self?.sendIntro()
            } catch {
                self?.logger.error("Error starting TCP service: \(error.localizedDescription)")
            }
        }
    }

    private func sendIntro() {
        guard let ip = NetworkUtils.getLocalIPv4Address() else {
            logger.error("--- Broker: Could not determine local IP for Intro ---")
            return
        }
        
        let deviceName = Host.current().localizedName ?? "MacBook"
        let intro = BridgerMessage(content: .intro(deviceName: deviceName, ip: ip, port: 41492))
        self.sendToTransport(intro)
    }

    private func sendToTransport(_ message: BridgerMessage) {
        guard let data = encryptionService.encryptMessage(message) else {
            logger.error("--- Broker: Encryption failed for outgoing message ---")
            return
        }
        Task { [weak self, data] in
            await self?.bluetoothService.send(data: data)
        }
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
