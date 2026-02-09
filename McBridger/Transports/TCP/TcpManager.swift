import Network
import Foundation
import OSLog
import Combine
import Factory

public actor TcpManager: TcpManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "TCP")
    
    @Injected(\.encryptionService) private var encryptionService: EncryptionServing
    
    nonisolated public let state = CurrentValueSubject<TcpConnectionState, Never>(.idle)
    nonisolated public let messages = PassthroughSubject<BridgerMessage, Never>()
    
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]

    public init() {
        logger.info("--- TcpManager: Initializing background instance ---")
    }

    public func start(port: Int) async throws {
        let parameters = Network.NWParameters.tcp
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
        for connection in activeConnections.values {
            connection.cancel()
        }
        activeConnections.removeAll()
        state.send(.idle)
    }

    private func onListenerStateUpdate(_ newState: Network.NWListener.State, port: Int) {
        switch newState {
        case .ready:
            state.send(.listening(port: port))
        case .failed(let error):
            state.send(.error(error.localizedDescription))
        default:
            break
        }
    }

    private func handleNewConnection(_ connection: Network.NWConnection) {
        let id = UUID()
        activeConnections[id] = connection
        
        connection.stateUpdateHandler = { [weak self] (newState: Network.NWConnection.State) in
            guard let self = self else { return }
            Task {
                await self.onConnectionStateUpdate(newState, connection: connection, id: id)
            }
        }
        connection.start(queue: .global())
    }

    private func onConnectionStateUpdate(_ newState: Network.NWConnection.State, connection: Network.NWConnection, id: UUID) {
        switch newState {
        case .ready:
            self.logger.info("TCP Connection ready: \(String(describing: connection.endpoint))")
            self.receiveLoop(connection, id: id)
        case .failed(let error):
            self.logger.error("TCP Connection failed: \(error.localizedDescription)")
            self.activeConnections.removeValue(forKey: id)
        case .cancelled:
            self.activeConnections.removeValue(forKey: id)
        default:
            break
        }
    }

    private func receiveLoop(_ connection: Network.NWConnection, id: UUID) {
        // Read 4 bytes length prefix
        connection.receive(minimumIncompleteLength: 4, maximumLength: 4) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            Task {
                if let error = error {
                    await self.logError("Receive length error: \(error.localizedDescription)")
                    return
                }
                
                guard let data = data, data.count == 4 else {
                    if isComplete { await self.removeConnection(id: id) }
                    return
                }
                
                let length = Int(data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian })
                
                // Read payload
                connection.receive(minimumIncompleteLength: length, maximumLength: length) { [weak self] data, _, isComplete, error in
                    guard let self = self else { return }
                    
                    Task {
                        if let error = error {
                            await self.logError("Receive payload error: \(error.localizedDescription)")
                            return
                        }
                        
                        if let data = data {
                            let address = String(describing: connection.endpoint)
                            await self.handleRawData(data, address: address)
                        }
                        
                        if !isComplete {
                            await self.receiveLoop(connection, id: id)
                        } else {
                            await self.removeConnection(id: id)
                        }
                    }
                }
            }
        }
    }

    private func removeConnection(id: UUID) {
        activeConnections.removeValue(forKey: id)
    }

    private func logError(_ message: String) {
        logger.error("\(message)")
    }

    private func handleRawData(_ data: Data, address: String) {
        do {
            let message = try BridgerMessage.fromData(data)
            messages.send(message)
        } catch {
            logger.error("Failed to deserialize TCP message: \(error.localizedDescription)")
        }
    }

    public func send(_ message: BridgerMessage) async throws {
        guard let payload = message.toData() else { return }
        
        var frame = Data()
        var length = UInt32(payload.count).bigEndian
        withUnsafeBytes(of: &length) { frame.append(contentsOf: $0) }
        frame.append(payload)
        
        for connection in activeConnections.values {
            connection.send(content: frame, completion: .contentProcessed({ [weak self] error in
                if let error = error {
                    Task { [weak self] in
                        await self?.logError("TCP send error: \(error.localizedDescription)")
                    }
                }
            }))
        }
    }

    public func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws {
        let endpoint = Network.NWEndpoint.hostPort(host: Network.NWEndpoint.Host(host), port: Network.NWEndpoint.Port(rawValue: UInt16(port))!)
        let connection = Network.NWConnection(to: endpoint, using: .tcp)
        
        return try await withCheckedThrowingContinuation { continuation in
            connection.stateUpdateHandler = { [weak self] (newState: Network.NWConnection.State) in
                guard let self = self else { return }
                switch newState {
                case .ready:
                    Task {
                        do {
                            // 1. Send Blob announcement
                            try await self.sendFrame(message, over: connection)
                            
                            // 2. Stream file in chunks
                            let fileHandle = try FileHandle(forReadingFrom: url)
                            let chunkSize = 64 * 1024 // 64KB
                            var offset: Int64 = 0
                            
                            while true {
                                guard let data = try fileHandle.read(upToCount: chunkSize), !data.isEmpty else {
                                    break
                                }
                                
                                let chunkMessage = BridgerMessage(
                                    content: .chunk(id: message.id, offset: offset, data: data),
                                    id: message.id
                                )
                                try await self.sendFrame(chunkMessage, over: connection)
                                offset += Int64(data.count)
                            }
                            
                            try fileHandle.close()
                            connection.cancel()
                            continuation.resume()
                            await self.logInfo("Successfully streamed blob \(message.id) to \(host)")
                        } catch {
                            connection.cancel()
                            continuation.resume(throwing: error)
                        }
                    }
                case .failed(let error):
                    continuation.resume(throwing: error)
                case .cancelled:
                    break
                default:
                    break
                }
            }
            connection.start(queue: .global())
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

    private func logInfo(_ message: String) {
        logger.info("\(message)")
    }
}
