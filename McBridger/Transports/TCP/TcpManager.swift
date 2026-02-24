import Network
import Foundation
import OSLog
import Combine
import Factory

public actor TcpManager: TcpManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "TCP")
    
    @Injected(\.encryptionService) private var encryptionService: EncryptionServing
    
    nonisolated public let state = CurrentValueSubject<TcpState, Never>(.idle)
    nonisolated public let messages = PassthroughSubject<BridgerMessage, Never>()
    
    private var listener: NWListener?
    private var activeConnection: NWConnection?
    private var outboundStream: AsyncStream<BridgerMessage>?
    private var outboundContinuation: AsyncStream<BridgerMessage>.Continuation?
    private var pendingPings: [String: CheckedContinuation<Void, Error>] = [:]
    
    public init() {
        logger.info("--- TcpManager: Initializing instance ---")
    }

    public func start(port: Int) async throws {
        guard listener == nil else {
            logger.warning("TCP Listener already active on port \(port). Ignoring.")
            return
        }
        
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.enableKeepalive = true
        tcpOptions.keepaliveIdle = 10
        tcpOptions.keepaliveInterval = 5
        tcpOptions.keepaliveCount = 3
        
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let listener = try Network.NWListener(using: parameters, on: Network.NWEndpoint.Port(rawValue: UInt16(port))!)
        
        listener.stateUpdateHandler = { [weak self] (newState: Network.NWListener.State) in
            guard let self = self else { return }
            Task {
                await self.onListenerStateUpdate(newState, port: port)
            }
        }
        
        listener.newConnectionHandler = { [weak self] (connection: Network.NWConnection) in
            guard let self = self else { return }
            Task { await self.handleNewConnection(connection) }
        }
        
        listener.start(queue: .global())
        self.listener = listener
        logger.info("TCP Listener started on port \(port)")
    }

    public func stop() async {
        listener?.cancel()
        listener = nil
        disconnectInternal()
        // Here we force state to idle because the listener is explicitly stopped
        if state.value != .idle {
            state.send(.idle)
        }
    }

    public func disconnect() async {
        disconnectInternal()
    }

    private func disconnectInternal() {
        activeConnection?.cancel()
        activeConnection = nil
        outboundContinuation?.finish()
        outboundContinuation = nil
        outboundStream = nil
        
        for (_, continuation) in pendingPings {
            continuation.resume(throwing: CancellationError())
        }
        pendingPings.removeAll()
        
        if state.value != .idle {
            if listener != nil {
                state.send(.ready)
            } else {
                state.send(.idle)
            }
        }
    }

    private func onListenerStateUpdate(_ newState: Network.NWListener.State, port: Int) {
        switch newState {
        case .ready:
            state.send(.ready)
        case .failed(let error):
            state.send(.error(error.localizedDescription))
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: Network.NWConnection) {
        setupActiveConnection(connection)
    }

    private func setupActiveConnection(_ connection: Network.NWConnection) {
        disconnectInternal()
        
        activeConnection = connection
        
        let (stream, continuation) = AsyncStream.makeStream(of: BridgerMessage.self, bufferingPolicy: .bufferingNewest(64))
        outboundStream = stream
        outboundContinuation = continuation
        
        connection.stateUpdateHandler = { [weak self] newState in
            guard let self = self else { return }
            Task { await self.onConnectionStateUpdate(newState, connection: connection) }
        }
        connection.start(queue: .global())
        
        Task { await self.writeLoop(connection: connection, stream: stream) }
    }

    private func onConnectionStateUpdate(_ newState: Network.NWConnection.State, connection: Network.NWConnection) {
        guard activeConnection === connection else { return }
        switch newState {
        case .ready:
            self.logger.info("TCP Connection ready: \(String(describing: connection.endpoint))")
            state.send(.connected(remoteAddress: String(describing: connection.endpoint)))
            self.receiveLoop(connection)
        case .failed(let error):
            self.logger.error("TCP Connection failed: \(error.localizedDescription)")
            self.disconnectInternal()
        case .cancelled:
            self.disconnectInternal()
        default:
            break
        }
    }

    private func writeLoop(connection: NWConnection, stream: AsyncStream<BridgerMessage>) async {
        for await message in stream {
            if connection.state != .ready && connection.state != .preparing { break }
            do {
                try await sendFrame(message, over: connection)
            } catch {
                logger.error("WriteLoop failed: \(error.localizedDescription)")
                disconnectInternal()
                break
            }
        }
    }

    private func receiveLoop(_ connection: Network.NWConnection) {
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            Task {
                guard await self.activeConnection === connection else { return }
                
                if let error = error {
                    self.logger.error("Receive length error: \(error.localizedDescription)")
                    await self.disconnectInternal()
                    return
                }
                
                guard let data = data, data.count == 4 else {
                    if isComplete { await self.disconnectInternal() }
                    return
                }
                
                let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
                    guard let self = self else { return }
                    
                    Task {
                        guard await self.activeConnection === connection else { return }
                        
                        if let error = error {
                            self.logger.error("Receive payload error: \(error.localizedDescription)")
                            await self.disconnectInternal()
                            return
                        }
                        
                        if let data = data {
                            let address = String(describing: connection.endpoint)
                            await self.handleRawData(data, address: address)
                        }
                        
                        if !isComplete {
                            await self.receiveLoop(connection)
                        } else {
                            await self.disconnectInternal()
                        }
                    }
                }
            }
        }
    }

    private func handleRawData(_ data: Data, address: String) {
        do {
            let message = try BridgerMessage.fromData(data)
            if case .ping = message.content {
                logger.debug("Received TCP Ping from \(address)")
                if let continuation = pendingPings.removeValue(forKey: message.id) {
                    continuation.resume()
                } else {
                    outboundContinuation?.yield(BridgerMessage(content: .ping, id: message.id))
                }
                return
            }
            
            let prevState = state.value
            if case .transferring = prevState {} else {
                state.send(.transferring(progress: 0))
            }
            
            messages.send(message)
            
            if case .transferring = prevState {} else {
                state.send(.connected(remoteAddress: address))
            }
            
        } catch {
            logger.error("Failed to deserialize TCP message: \(error.localizedDescription)")
        }
    }

    public func forcePing() async throws {
        let currentState = state.value
        if case .transferring = currentState { return }
        
        guard case .connected = currentState else {
            throw BridgerMessageError.corruptData
        }
        
        guard let outStream = outboundContinuation else {
            throw BridgerMessageError.corruptData
        }
        
        let ping = BridgerMessage(content: .ping)
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    Task { await self.setPendingPing(id: ping.id, continuation: c) }
                    outStream.yield(ping)
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 2_000_000_000)
                throw CancellationError()
            }
            
            do {
                try await group.next()
                group.cancelAll()
            } catch {
                group.cancelAll()
                await self.disconnectInternal()
                throw error
            }
        }
    }

    private func setPendingPing(id: String, continuation: CheckedContinuation<Void, Error>) {
        pendingPings[id] = continuation
    }

    public func send(_ message: BridgerMessage) async throws {
        outboundContinuation?.yield(message)
    }

    public func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws {
        if activeConnection == nil {
            let endpoint = Network.NWEndpoint.hostPort(host: Network.NWEndpoint.Host(host), port: Network.NWEndpoint.Port(rawValue: UInt16(port))!)
            let connection = Network.NWConnection(to: endpoint, using: .tcp)
            setupActiveConnection(connection)
        }
        
        let prevState = state.value
        state.send(.transferring(progress: 0))
        
        do {
            outboundContinuation?.yield(message)
            
            let fileHandle = try FileHandle(forReadingFrom: url)
            defer { try? fileHandle.close() }
            
            let chunkSize = 64 * 1024
            var offset: Int64 = 0
            let totalSize = message.content.blobSize ?? 0
            
            while let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty {
                let chunkMessage = BridgerMessage(content: .chunk(id: message.id, offset: offset, data: data), id: message.id)
                outboundContinuation?.yield(chunkMessage)
                offset += Int64(data.count)
                
                if totalSize > 0 {
                    state.send(.transferring(progress: Double(offset) / Double(totalSize)))
                }
            }
            logger.info("Blob send finished: \(offset) bytes")
            
            if case .transferring = state.value {
                state.send(prevState)
            }
        } catch {
            logger.error("Blob send failed: \(error.localizedDescription)")
            if case .transferring = state.value {
                state.send(prevState)
            }
            throw error
        }
    }

    private func sendFrame(_ message: BridgerMessage, over connection: Network.NWConnection) async throws {
        guard let payload = message.toData() else {
            throw BridgerMessageError.corruptData
        }
        
        var frame = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.send(content: frame, completion: .contentProcessed({ error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }))
        }
    }
}
