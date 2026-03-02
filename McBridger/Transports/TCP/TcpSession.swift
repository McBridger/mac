import Combine
import Foundation
import Network

private enum Constants {
    static let framePing: Int32 = 0
    static let framePong: Int32 = -1
    static let maxPayloadSize: Int32 = 10 * 1024 * 1024
}

// MARK: - TcpSession (Actor)
// Sole owner of the socket, isolates the Data Plane (read/write/pings)
public actor TcpSession: ITcpSession {
    public let id: String
    public let host: String
    public let port: Int

    public let stateUpdates: AsyncStream<SessionState>
    private let stateContinuation: AsyncStream<SessionState>.Continuation

    public let incomingMessages: AsyncStream<Data>
    private let messagesContinuation: AsyncStream<Data>.Continuation

    private let connection: NWConnection
    private var isPingEnabled: Bool = false

    // FIFO queue of pending pings. Each entry carries a UUID for safe identity-based
    // timeout resolution. TCP ordering guarantees PONGs arrive in the same order as PINGs.
    private struct PendingPing {
        let id: UUID
        let continuation: CheckedContinuation<Void, Swift.Error>
        let timeoutTask: Task<Void, Never>
    }
    private var pendingPings: [PendingPing] = []

    public init(
        id: String,
        host: String,
        port: Int,
        connection: NWConnection
    ) {
        self.id = id
        self.host = host
        self.port = port
        self.connection = connection

        let stateStream = AsyncStream<SessionState>.makeStream()
        self.stateUpdates = stateStream.stream
        self.stateContinuation = stateStream.continuation

        let msgStream = AsyncStream<Data>.makeStream()
        self.incomingMessages = msgStream.stream
        self.messagesContinuation = msgStream.continuation

        self.stateContinuation.yield(.connecting)
    }

    public func start() {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            Task { await self.handleConnectionState(state) }
        }
        connection.start(queue: .global())

        // Start application level heartbeat loop
        Task { await self.pingLoop() }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            stateContinuation.yield(.connected)
            Task { await self.receiveLoop() }
        case .cancelled:
            // Using print for now to match prototype, can be updated to Logger later if needed.
            print("[TCP] Connection cancelled")
            die(.error, "handleConnectionState-cancelled")
        case .failed(let err):
            print("[TCP] Connection failed with error: \(err)")
            die(.error, "handleConnectionState-failed")
        default:
            break
        }
    }

    private func receiveData(min: Int, max: Int) async throws -> (Data?, Bool) {
        try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: min, maximumLength: max) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (data, isComplete))
                }
            }
        }
    }

    private func receiveLoop() async {
        do {
            while true {
                let (lengthData, isLengthComplete) = try await receiveData(min: 4, max: 4)

                // EOF: peer closed the connection gracefully
                guard !isLengthComplete else {
                    die(.disconnected, "receiveLoop-EOF")
                    break
                }

                guard let lData = lengthData, lData.count == 4 else {
                    // nil data without isComplete is a network error, not graceful close
                    die(.error, "receiveLoop-nilLengthData")
                    break
                }

                let length = lData.withUnsafeBytes { $0.load(as: Int32.self).bigEndian }

                // Guard clause: Ping
                guard length != Constants.framePing else {
                    try? await self.sendLengthAndData(length: Constants.framePong, data: nil)
                    continue
                }

                // Guard clause: Pong — resolve oldest pending ping (FIFO = TCP order)
                guard length != Constants.framePong else {
                    resolveOldestPing(with: .success(()))
                    continue
                }

                // Guard clause: Validate size
                guard length > Constants.framePong && length <= Constants.maxPayloadSize else {
                    throw TransportError.notConnected
                }

                let payLoadLength = Int(length)
                let (payloadData, isPayloadComplete) = try await receiveData(min: payLoadLength, max: payLoadLength)

                // EOF mid-payload: connection closed while we were reading
                guard !isPayloadComplete else {
                    die(.disconnected, "receiveLoop-payloadEOF")
                    break
                }

                guard let payload = payloadData else {
                    // nil without EOF is a network error
                    die(.error, "receiveLoop-nilPayloadData")
                    break
                }

                messagesContinuation.yield(payload)
            }
        } catch {
            print("[TCP] receiveLoop failed with error: \(error)")
            die(.error, "receiveLoop-catch")
        }
    }

    // --- Data Plane ---

    public func send(_ data: Data) async throws {
        guard case .ready = connection.state else { throw TransportError.notConnected }
        try await sendLengthAndData(length: Int32(data.count), data: data)
    }

    private func sendLengthAndData(length: Int32, data: Data?) async throws {
        var header = Data()
        var len = length.bigEndian
        withUnsafeBytes(of: &len) { header.append(contentsOf: $0) }

        return try await withCheckedThrowingContinuation { continuation in
            if let data = data, !data.isEmpty {
                connection.send(content: header, isComplete: false, completion: .contentProcessed { _ in })
                connection.send(content: data, isComplete: false, completion: .contentProcessed { error in
                    guard let error = error else {
                        continuation.resume()
                        return
                    }
                    continuation.resume(throwing: error)
                })
                return
            }

            connection.send(content: header, isComplete: false, completion: .contentProcessed { error in
                guard let error = error else {
                    continuation.resume()
                    return
                }
                continuation.resume(throwing: error)
            })
        }
    }

    // --- Ping Logic ---

    private func pingLoop() async {
        while case .ready = connection.state {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard isPingEnabled, case .ready = connection.state else { continue }
            try? await forcePing()
        }
    }

    public func setPingEnabled(_ enabled: Bool) {
        isPingEnabled = enabled
    }

    public func forcePing() async throws {
        guard case .ready = connection.state else { throw TransportError.notConnected }

        let pingId = UUID()

        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Swift.Error>) in
            // Spawn timeout task that identifies itself by pingId, not by array index.
            // This is safe even if earlier pings resolve and shift the array.
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                guard !Task.isCancelled else { return }
                await self.resolvePing(id: pingId, with: .failure(TransportError.timedOut))
            }

            pendingPings.append(PendingPing(id: pingId, continuation: c, timeoutTask: timeoutTask))

            Task {
                do {
                    try await self.sendLengthAndData(length: Constants.framePing, data: nil)
                } catch {
                    await self.resolvePing(id: pingId, with: .failure(error))
                }
            }
        }
    }

    // Resolves the oldest pending ping (called on PONG — TCP FIFO ensures correct order).
    private func resolveOldestPing(with result: Result<Void, Swift.Error>) {
        guard !pendingPings.isEmpty else { return }
        let ping = pendingPings.removeFirst()
        ping.timeoutTask.cancel()
        ping.continuation.resume(with: result)
    }

    // Resolves a specific ping by UUID (called by timeout tasks).
    nonisolated private func resolvePing(id: UUID, with result: Result<Void, Swift.Error>) async {
        Task {
            await self.resolvePingInternal(id: id, with: result)
        }
    }
    
    private func resolvePingInternal(id: UUID, with result: Result<Void, Swift.Error>) {
        guard let index = pendingPings.firstIndex(where: { $0.id == id }) else { return }
        let ping = pendingPings.remove(at: index)
        ping.timeoutTask.cancel()
        ping.continuation.resume(with: result)

        if case .failure = result {
            die(.error, "ping timeout \(id)")
        }
    }

    // --- Lifecycle ---

    public func disconnect() {
        die(.disconnected, "disconnect()")
    }

    private func die(_ finalState: SessionState, _ source: String) {
        print("[TCP] Session die() invoked from \(source). current NW state: \(connection.state), final: \(finalState)")

        // Drain all pending pings so their awaiters unblock immediately
        pendingPings.forEach { ping in
            ping.timeoutTask.cancel()
            ping.continuation.resume(throwing: URLError(.cancelled))
        }
        pendingPings.removeAll()

        connection.cancel()
        stateContinuation.yield(finalState)

        stateContinuation.finish()
        messagesContinuation.finish()
    }
}
