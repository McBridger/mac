import Vapor
import Foundation
import OSLog
import Combine
import Factory

public actor TcpManager: TcpManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "TCP")
    
    @Injected(\.encryptionService) private var encryptionService: EncryptionServing
    @Injected(\.tcpFileProvider) private var fileProvider: TcpFileProviding
    
    nonisolated public let state = CurrentValueSubject<TcpConnectionState, Never>(.idle)
    nonisolated public let messages = PassthroughSubject<BridgerMessage, Never>()
    
    private var app: Application?
    private var activeWebSocket: WebSocket?

    public init() {
        logger.info("--- TcpManager: Initializing background instance ---")
    }

    public func start(port: Int) async throws {
        // 1. Setup Vapor Application
        var env = try Environment.detect()
        env.arguments = ["vapor"]

        let app = try await Application.make(env)
        app.http.server.configuration.port = port
        app.http.server.configuration.hostname = "0.0.0.0"

        // 2. WebSocket Route for Messaging
        app.webSocket("bridge") { [weak self] req, ws in
            guard let self = self else { return }
            
            await self.handleNewConnection(ws)
            
            ws.onBinary { ws, buffer in
                let data = Data(buffer.readableBytesView)
                Task {
                    await self.handleRawData(data, address: req.remoteAddress?.description ?? "unknown")
                }
            }
            
            _ = ws.onClose.always { _ in
                Task {
                    await self.handleNewConnection(nil)
                }
            }
        }

        // 3. HTTP Route for File Serving
        app.get("files", ":id", ":name") { [weak self] req -> Response in
            guard let self = self else { throw Abort(.internalServerError) }
            
            let id = req.parameters.get("id") ?? ""
            guard let fileURL = await self.fileProvider.getFileURL(id: id) else {
                throw Abort(.notFound)
            }
            
            self.logger.info("Serving file: \(fileURL.lastPathComponent)")
            
            // Vapor's fileio handles ranges (resume/partial) automatically!
            return req.fileio.streamFile(at: fileURL.path)
        }

        self.app = app
        state.send(.listening(port: port))
        
        // Start the server in a separate task so it doesn't block the caller
        Task.detached {
            do {
                try await app.execute()
            } catch {
                self.logger.error("Vapor server error: \(error.localizedDescription)")
            }
        }
    }

    public func stop() async {
        try? await app?.shutdown()
        app = nil
        activeWebSocket = nil
        state.send(.idle)
    }

    private func handleNewConnection(_ ws: WebSocket?) {
        self.activeWebSocket = ws
        if ws != nil {
            logger.info("TCP WebSocket connected")
        } else {
            logger.info("TCP WebSocket disconnected")
        }
    }

    private func handleRawData(_ data: Data, address: String) {
        do {
            let message = try encryptionService.decryptMessage(data, address: address)
            messages.send(message)
        } catch {
            logger.error("Failed to decrypt TCP message: \(error.localizedDescription)")
        }
    }

    public func send(_ message: BridgerMessage) async throws {
        guard let data = encryptionService.encryptMessage(message),
              let ws = activeWebSocket else {
            return
        }
        
        try await ws.send(raw: data, opcode: .binary)
    }

    public func registerFile(at url: URL, name: String) async -> String {
        return await fileProvider.registerFile(at: url)
    }
}
