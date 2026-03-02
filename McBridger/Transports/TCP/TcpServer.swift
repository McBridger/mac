import Foundation
import Network
import OSLog

// TcpServer is RAII: it's born alive (via make()) and cleans up on stop() or deallocation (deinit).
// Do NOT call start() — it doesn't exist. To "restart", create a new instance via make().
// Sessions are created INTERNALLY — NWConnection never leaks into the public API.
public actor TcpServer: ITcpServer {

    public let stateUpdates: AsyncStream<ServerState>
    private let stateContinuation: AsyncStream<ServerState>.Continuation

    public let newSessions: AsyncStream<any ITcpSession>
    private let newSessionsContinuation: AsyncStream<any ITcpSession>.Continuation

    private var listener: NWListener?

    private init() {
        let stateStream = AsyncStream<ServerState>.makeStream()
        self.stateUpdates = stateStream.stream
        self.stateContinuation = stateStream.continuation

        let sessionStream = AsyncStream<any ITcpSession>.makeStream()
        self.newSessions = sessionStream.stream
        self.newSessionsContinuation = sessionStream.continuation
    }

    // The only way to create a live TcpServer. Returns only after the listener is ready.
    public static func make(port: Int) async throws -> TcpServer {
        let server = TcpServer()
        try await server.boot(port: port)
        return server
    }

    private func boot(port: Int) async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true

        let newListener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: UInt16(port))!)

        let sCont = stateContinuation
        let cCont = newSessionsContinuation

        // Block until the listener is actually ready (or fails).
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let resumeLock = OSAllocatedUnfairLock(initialState: false)

            newListener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    sCont.yield(.listening)
                    resumeLock.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        cont.resume()
                    }
                case .failed(let error):
                    sCont.yield(.error)
                    resumeLock.withLock { alreadyResumed in
                        guard !alreadyResumed else { return }
                        alreadyResumed = true
                        cont.resume(throwing: error)
                    }
                case .cancelled:
                    sCont.yield(.stopped)
                default:
                    break
                }
            }

            // Sessions are created internally here — NWConnection never leaks upward.
            newListener.newConnectionHandler = { connection in
                var hostName = "unknown"
                var portNum = 0
                if case .hostPort(let host, let port) = connection.endpoint {
                    hostName = "\(host)"
                    portNum = Int(port.rawValue)
                }
                let session = TcpSession(
                    id: UUID().uuidString,
                    host: hostName,
                    port: portNum,
                    connection: connection
                )
                Task { await session.start() }
                cCont.yield(session)
            }

            newListener.start(queue: .global())
            self.listener = newListener
            sCont.yield(.starting)
        }
    }

    public var isListening: Bool {
        listener != nil
    }

    // Explicit stop — should be preferred over relying on ARC/deinit for resource cleanup.
    // After stop(), the streams are finished and the port is released immediately.
    public func stop() {
        listener?.cancel()
        listener = nil
        stateContinuation.finish()
        newSessionsContinuation.finish()
    }

    deinit {
        // Synchronous cleanup as a safety net if stop() was not called
        listener?.cancel()
        stateContinuation.finish()
        newSessionsContinuation.finish()
    }
}
