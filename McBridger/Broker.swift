import Foundation
import Factory
import Combine
import OSLog
import AppKit

/// Broker runs on background threads to handle orchestration, encryption, and transport.
public final class Broker: @unchecked Sendable {
    private let logger = Logger(subsystem: "com.mcbridger.Core", category: "Broker")
    private let queue = DispatchQueue(label: "com.mcbridger.broker-queue", qos: .userInitiated)
    
    // MARK: - Subjects
    public let state = CurrentValueSubject<BrokerState, Never>(.idle)
    
    // MARK: - Services
    @Injected(\.clipboardManager) private var clipboardService: ClipboardManaging
    @Injected(\.encryptionService) private var encryptionService: EncryptionServing
    @Injected(\.notificationService) private var notificationService
    @Injected(\.bluetoothManager) private var bluetoothService: BluetoothManaging
    @Injected(\.tcpManager) private var tcpService: TcpManaging
    @Injected(\.blobStorageManager) private var blobStorageService: BlobStorageManaging
    @Injected(\.wakeManager) private var wakeManager: WakeManaging
    @Injected(\.historyManager) private var historyManager: HistoryManaging
    @Injected(\.systemObserver) private var systemObserver: SystemObserving
    
    private var cancellables = Set<AnyCancellable>()
    private var partnerTcpTarget: (ip: String, port: Int)?
    private var isBootstrapped = false

    public init() {
        logger.info("--- Broker: Initializing ---")
    }

    public func bootstrap() {
        queue.async { [weak self] in
            guard let self = self, !self.isBootstrapped else { return }
            self.isBootstrapped = true
            self.logger.info("--- Broker: Bootstrapping ---")
            
            // 1. Sync Base State (Pure Projection)
            Publishers.CombineLatest3(
                self.bluetoothService.connection,
                self.tcpService.state,
                self.encryptionService.isReady
            ).receive(on: self.queue)
            .sink { [weak self] ble, tcp, encReady in
                guard let self = self else { return }
                self.mutateStateInternal { s in
                    s.ble = .init(current: ble)
                    s.tcp = .init(current: tcp)
                    s.encryption = .init(current: encReady ? .keysReady : .idle)
                }
            }.store(in: &self.cancellables)

            // 1b. Transport Trigger (Logic)
            self.encryptionService.isReady
                .removeDuplicates()
                .filter { $0 }
                .receive(on: self.queue)
                .sink { [weak self] _ in
                    self?.setupTransport()
                }
                .store(in: &self.cancellables)

            // 2. Incoming Pipeline
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

            // 3. Outgoing: Clipboard Watch
            self.clipboardService.update
                .receive(on: self.queue)
                .sink { [weak self] message in self?.onLocalClipboardUpdate(message) }
                .store(in: &self.cancellables)
                
            // 4. Network Watchdog
            self.systemObserver.localIpAddress
                .dropFirst()
                .removeDuplicates()
                .receive(on: self.queue)
                .sink { [weak self] ip in
                    guard let self = self else { return }
                    if let ip = ip {
                        self.logger.info("IP restored (\(ip)). Restarting TCP service and notifying partner.")
                        Task {
                            try? await self.tcpService.start(port: 41492)
                            self.sendIntro()
                        }
                    } else {
                        self.logger.warning("IP lost. Stopping TCP and notifying partner.")
                        Task { await self.tcpService.stop() }
                        self.sendIntro(forceEmpty: true)
                    }
                }.store(in: &self.cancellables)
        }
    }
    
    // MARK: - Handlers

    private func onIncomingUpdate(_ message: BridgerMessage) {
        dispatchPrecondition(condition: .onQueue(queue))
        switch message.content {
        case .tiny(let text):
            let porter = Porter(
                isOutgoing: false,
                status: .completed,
                name: "Text Message",
                type: .text,
                totalSize: Int64(text.utf8.count),
                data: text
            )
            finalizePorter(porter)
            clipboardService.setText(text)
            notificationService.showNotification(title: "Message Synced", body: text)

        case .intro(let deviceName, let ip, let port):
            if let ip = ip, let port = port {
                self.partnerTcpTarget = (ip, port)
                if let address = message.address, let uuid = UUID(uuidString: address) {
                    Task { await self.bluetoothService.markDeviceAsIntroduced(id: uuid, name: deviceName) }
                }
                sendIntro()
            } else {
                self.logger.warning("Partner sent empty intro. Disconnecting current session.")
                self.partnerTcpTarget = nil
                Task {
                    await self.tcpService.disconnect()
                }
            }

        case .blob(let name, let size, let blobType):
            let porter = Porter(id: message.id, isOutgoing: false, name: name, type: blobType, totalSize: size)
            updatePorterInternal(porter)
            Task { try? await self.blobStorageService.registerBlob(id: message.id, name: name, size: size, type: blobType) }

        case .chunk(let id, let offset, let data):
            _ = updatePorterProgressInternal(id: id, offset: offset, dataSize: data.count)
            Task {
                if let isComplete = try? await self.blobStorageService.handleChunk(id: id, offset: offset, data: data), isComplete {
                    if let url = try? await self.blobStorageService.finalizeBlob(id: id) {
                        self.queue.async { [weak self] in
                            self?.onBlobAssembled(id: id, url: url)
                        }
                    }
                }
            }
            
        case .ping:
            break
        }
    }

    private func onLocalClipboardUpdate(_ message: BridgerMessage) {
        dispatchPrecondition(condition: .onQueue(queue))
        let name: String
        let type: BlobType
        let size: Int64
        let data: String?
        
        switch message.content {
        case .tiny(let text):
            name = "Clipboard Text"
            type = .text
            size = Int64(text.utf8.count)
            data = text
        case .blob(let fileName, let fileSize, let bType):
            name = fileName
            type = bType
            size = fileSize
            data = message.address // File URL string
        default: return
        }
        
        let porter = Porter(isOutgoing: true, name: name, type: type, totalSize: size, data: data)
        handleOutgoing(porter)
    }

    private func handleOutgoing(_ porter: Porter) {
        dispatchPrecondition(condition: .onQueue(queue))
        var p = porter
        p.status = .active
        updatePorterInternal(p)
        
        if p.totalSize > 500 {
            sendBlobViaTcp(p)
        } else {
            sendTinyViaBle(p)
        }
    }

    private func sendTinyViaBle(_ porter: Porter) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let text = porter.data else { return }
        let message = BridgerMessage(content: .tiny(text: text))
        sendToTransport(message)
        
        var completed = porter
        completed.status = .completed
        completed.progress = 1.0
        finalizePorter(completed)
    }

    private func sendBlobViaTcp(_ porter: Porter) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let target = partnerTcpTarget, let urlString = porter.data else {
            var errorPorter = porter
            errorPorter.status = .error
            errorPorter.error = "No TCP target or invalid URL"
            finalizePorter(errorPorter)
            return
        }
        
        Task { [weak self] in
            guard let self = self else { return }
            await self.wakeManager.acquire(reason: "Sending \(porter.name)")
            
            do {
                let url: URL
                if porter.type == .text {
                    url = try await self.blobStorageService.createTempFile(for: urlString, id: porter.id)
                } else {
                    guard let fURL = URL(string: urlString) else { throw BridgerMessageError.corruptData }
                    url = fURL
                }

                let message = BridgerMessage(
                    content: .blob(name: porter.name, size: porter.totalSize, blobType: porter.type),
                    id: porter.id
                )
                try await self.tcpService.sendBlob(message, url: url, to: target.ip, port: target.port)
                
                var completed = porter
                completed.status = .completed
                completed.progress = 1.0
                self.finalizePorter(completed)
            } catch {
                var errorPorter = porter
                errorPorter.status = .error
                errorPorter.error = error.localizedDescription
                self.finalizePorter(errorPorter)
            }
            
            await self.wakeManager.release()
        }
    }

    private func onBlobAssembled(id: String, url: URL) {
        dispatchPrecondition(condition: .onQueue(queue))
        guard let porter = self.state.value.activePorters[id] else { return }
        
        var completed = porter
        completed.status = .completed
        completed.progress = 1.0
        
        finalizePorter(completed)
        
        Task { [weak self] in
            guard let self = self else { return }
            if porter.type == .text {
                if let text = try? String(contentsOf: url) {
                    self.clipboardService.setText(text)
                }
            } else {
                self.clipboardService.setFile(url: url)
            }
        }
        
        self.notificationService.showNotification(title: "Transfer Complete", body: url.lastPathComponent)
    }

    // MARK: - State & SSOT Isolation

    private func updatePorterInternal(_ porter: Porter) {
        dispatchPrecondition(condition: .onQueue(queue))
        mutateStateInternal { $0.activePorters[porter.id] = porter }
    }

    private func updatePorterProgressInternal(id: String, offset: Int64, dataSize: Int) -> Bool {
        dispatchPrecondition(condition: .onQueue(queue))
        guard var porter = state.value.activePorters[id] else { return false }
        porter.status = .active
        porter.currentSize = offset + Int64(dataSize)
        porter.progress = Double(porter.currentSize) / Double(porter.totalSize)
        mutateStateInternal { $0.activePorters[id] = porter }
        
        return porter.currentSize >= porter.totalSize
    }

    private func finalizePorter(_ porter: Porter) {
        Task { [weak self, historyManager] in
            // 1. Wait for history to persist record (Actor ensures serial consistency)
            await historyManager.addOrUpdate(porter)
            
            // 2. Clear from active set and push state update
            self?.queue.async { [weak self] in
                guard let self = self else { return }
                self.mutateStateInternal { $0.activePorters.removeValue(forKey: porter.id) }
            }
        }
    }

    private func mutateStateInternal(_ block: (inout BrokerState) -> Void) {
        var s = state.value
        block(&s)
        state.send(s)
    }

    // MARK: - Internal Transport logic

    private func setupTransport() {
        dispatchPrecondition(condition: .onQueue(queue))
        
        guard let advID = encryptionService.derive(info: "McBridge_Advertise_UUID", count: 16),
              let svcID = encryptionService.derive(info: "McBridge_Service_UUID", count: 16),
              let chrID = encryptionService.derive(info: "McBridge_Characteristic_UUID", count: 16) else {
            return
        }
        
        logger.info("🚀 Starting transports...")
        
        Task { [weak self, advID, svcID, chrID] in
            await self?.bluetoothService.start(advertise: advID, service: svcID, characteristic: chrID)
        }
        
        Task { [weak self] in
            try? await self?.tcpService.start(port: 41492)
            self?.sendIntro()
        }
    }

    private func sendIntro(forceEmpty: Bool = false) {
        let ip = forceEmpty ? nil : systemObserver.localIpAddress.value
        let port = ip == nil ? nil : 41492
        let deviceName = Host.current().localizedName ?? "MacBook"
        let intro = BridgerMessage(content: .intro(deviceName: deviceName, ip: ip, port: port))
        sendToTransport(intro)
    }

    private func sendToTransport(_ message: BridgerMessage) {
        guard let data = encryptionService.encryptMessage(message) else { return }
        Task { await self.bluetoothService.send(data: data) }
    }
    
    // MARK: - Public Control

    public func setup(mnemonic: String) {
        queue.async { [weak self] in
            self?.encryptionService.setup(with: mnemonic)
        }
    }
    
    public func reset() {
        queue.async { [weak self] in
            guard let self = self else { return }
            Task { [weak self] in
                await self?.bluetoothService.stop()
                await self?.tcpService.stop()
            }
            self.encryptionService.reset()
            Task {
                await self.historyManager.clear()
            }
            self.mutateStateInternal { $0.activePorters = [:] }
        }
    }
    
    private func decrypt(data: Data, address: String?) -> AnyPublisher<BridgerMessage, Never> {
        Just((data, address))
            .tryMap { [weak self] d, a in
                try self?.encryptionService.decryptMessage(d, address: a)
            }
            .compactMap { $0 }
            .catch { _ in Empty<BridgerMessage, Never>() }
            .eraseToAnyPublisher()
    }
}
