import Combine
import Foundation
import OSLog
import Network

// MARK: - TcpTransport
// Lifecycle manager (Control Plane), non-blocking during data transfer
public final class TcpTransport: TcpManaging {

    public let state = CurrentValueSubject<TcpState, Never>(.idle)
    public let messages = PassthroughSubject<BridgerMessage, Never>()

    private let serverFactory: TcpServerFactory = { port in
        try await TcpServer.make(port: port)
    }
    
    private let connectionFactory: TcpConnectionFactory = { host, port in
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: UInt16(port))!)
        let session = TcpSession(
            id: UUID().uuidString,
            host: host,
            port: port,
            connection: NWConnection(to: endpoint, using: .tcp)
        )
        await session.start()
        return session
    }

    private let stateActor: TransportStateActor
    private var actorObservationTask: Task<Void, Never>?

    public init() {
        self.stateActor = TransportStateActor()

        self.actorObservationTask = Task { [weak self] in
            guard let self = self else { return }
            for await status in await stateActor.statusUpdates {
                let newState = self.mapRawStatusToState(status)
                if self.state.value != newState {
                    self.state.send(newState)
                }
            }
        }
    }

    private func mapRawStatusToState(_ status: RawStatus) -> TcpState {
        guard status.isStarted else { return .idle }
        if status.isTransferring { return .transferring(progress: 0) } // Progress tracking could be improved
        if status.sessionCount > 0 { 
            return .connected(remoteAddress: "Multiple sessions (\(status.sessionCount))")
        }
        if status.isListening { return .ready }
        return .idle
    }

    public func start(port: Int) async throws {
        let server = try await serverFactory(port)

        guard await server.isListening else { return }
        
        let stateTask = Task { [weak self] in
            for await serverState in server.stateUpdates {
                await self?.stateActor.handleServerState(serverState)
            }
        }

        let connTask = Task { [weak self] in
            for await session in server.newSessions {
                await self?.setupNewSession(session)
            }
        }

        await stateActor.setServer(server, tasks: [stateTask, connTask])
        await stateActor.setIsStarted(true)
    }

    public func connect(host: String, port: Int) async {
        do {
            let session = try await connectionFactory(host, port)
            await setupNewSession(session)
        } catch {
            print("[TcpTransport] Outbound connect failed: \(error)")
        }
    }
    
    // For backward compatibility with TcpManaging (non-async version if needed, but TcpManaging has async)
    public func disconnect() async {
        await stop()
    }

    private func setupNewSession(_ session: any ITcpSession) async {
        let id = session.id

        let stateTask = Task { [weak self] in
            for await sessionState in session.stateUpdates {
                if sessionState == .disconnected || sessionState == .error {
                    await self?.handleSessionDeath(for: id)
                }
            }
        }

        let messageTask = Task { [weak self] in
            for await data in session.incomingMessages {
                guard let self = self else { return }
                do {
                    let parsedMessage = try BridgerMessage.fromData(data)
                    self.messages.send(parsedMessage)
                } catch {
                    print("[TcpTransport] Failed to parse BridgerMessage: \(error)")
                }
            }
        }

        await stateActor.addSession(id: id, session: session, tasks: [stateTask, messageTask])
    }

    private func handleSessionDeath(for id: String) async {
        let (deadSession, tasks) = await stateActor.removeSession(id: id)

        tasks?.forEach { $0.cancel() }

        if let session = deadSession {
            Task { await session.disconnect() }
        }
    }

    // --- Data Plane Proxies ---

    public func send(_ message: BridgerMessage) async throws {
        guard let data = message.toData() else { return }
        let sessions = await stateActor.getSessions()
        guard !sessions.isEmpty else {
            throw TransportError.notConnected
        }

        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { try? await session.send(data) }
            }
        }
    }

    public func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws {
        // If not connected to this host/port, try to connect first
        let sessions = await stateActor.getSessions()
        if !sessions.contains(where: { $0.host == host && $0.port == port }) {
            await connect(host: host, port: port)
        }
        
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let fileSize = attributes[.size] as? Int64 ?? 0
        let name = url.lastPathComponent

        let transferTargets = await stateActor.getSessions()
        guard !transferTargets.isEmpty else { throw TransportError.notConnected }

        let blobMsg = BridgerMessage(content: .blob(name: name, size: fileSize, blobType: .file), id: message.id)
        guard let blobData = blobMsg.toData() else { return }

        await stateActor.setIsTransferring(true)
        defer { Task { await stateActor.setIsTransferring(false) } }

        await withTaskGroup(of: Void.self) { group in
            for session in transferTargets {
                group.addTask { try? await session.send(blobData) }
            }
        }

        let fileHandle = try FileHandle(forReadingFrom: url)
        defer { try? fileHandle.close() }

        let chunkSize = 64 * 1024
        var offset: Int64 = 0

        while true {
            let chunk = try fileHandle.read(upToCount: chunkSize)
            guard let data = chunk, !data.isEmpty else { break }

            let chunkMsg = BridgerMessage(content: .chunk(id: blobMsg.id, offset: offset, data: data), id: blobMsg.id)
            guard let chunkData = chunkMsg.toData() else { break }

            await withTaskGroup(of: Void.self) { group in
                for session in transferTargets {
                    group.addTask { try? await session.send(chunkData) }
                }
            }

            offset += Int64(data.count)
            await Task.yield()
        }

        let eofMsg = BridgerMessage(content: .chunk(id: blobMsg.id, offset: offset, data: Data()), id: blobMsg.id)
        if let eofData = eofMsg.toData() {
            await withTaskGroup(of: Void.self) { group in
                for session in transferTargets {
                    group.addTask { try? await session.send(eofData) }
                }
            }
        }
    }

    public func setPingEnabled(_ enabled: Bool) {
        Task {
            let sessions = await stateActor.getSessions()
            for session in sessions {
                await session.setPingEnabled(enabled)
            }
        }
    }

    public func forcePing() async throws {
        let sessions = await stateActor.getSessions()
        guard !sessions.isEmpty else {
            throw TransportError.notConnected
        }

        await withTaskGroup(of: Void.self) { group in
            for session in sessions {
                group.addTask { try? await session.forcePing() }
            }
        }
    }

    public func stop() async {
        let (serverToStop, serverTasksToKill, sessionsToKill) = await stateActor.takeAllForStop()

        for task in serverTasksToKill { task.cancel() }

        if let server = serverToStop { await server.stop() }

        await withTaskGroup(of: Void.self) { group in
            for session in sessionsToKill {
                group.addTask { await session.disconnect() }
            }
        }
    }
}

// MARK: - Internal State Models

struct RawStatus: Equatable {
    let isStarted: Bool
    let isListening: Bool
    let isTransferring: Bool
    let sessionCount: Int
}

private actor TransportStateActor {
    var server: (any ITcpServer)?
    var serverTasks: [Task<Void, Never>] = []
    var activeSessions: [String: any ITcpSession] = [:]
    var sessionTasks: [String: [Task<Void, Never>]] = [:]

    private let statusContinuation: AsyncStream<RawStatus>.Continuation
    public let statusUpdates: AsyncStream<RawStatus>

    private var isStarted = false
    private var isTransferring = false
    private var isListening = false

    init() {
        let stream = AsyncStream<RawStatus>.makeStream()
        self.statusUpdates = stream.stream
        self.statusContinuation = stream.continuation
    }

    private func notifyStatusChange() {
        let status = RawStatus(
            isStarted: isStarted,
            isListening: isListening,
            isTransferring: isTransferring,
            sessionCount: activeSessions.count
        )
        statusContinuation.yield(status)
    }

    func setIsStarted(_ started: Bool) {
        isStarted = started
        notifyStatusChange()
    }

    func setIsTransferring(_ transferring: Bool) {
        isTransferring = transferring
        notifyStatusChange()
    }

    func handleServerState(_ state: ServerState) {
        switch state {
        case .listening:
            isListening = true
        case .error, .stopped:
            isListening = false
        default: break
        }
        notifyStatusChange()
    }

    func setServer(_ newServer: any ITcpServer, tasks: [Task<Void, Never>]) async {
        self.server = newServer
        self.serverTasks = tasks
        self.isListening = await newServer.isListening
        notifyStatusChange()
    }

    func addSession(id: String, session: any ITcpSession, tasks: [Task<Void, Never>]) {
        activeSessions[id] = session
        sessionTasks[id] = tasks
        notifyStatusChange()
    }

    func removeSession(id: String) -> ((any ITcpSession)?, [Task<Void, Never>]?) {
        let session = activeSessions.removeValue(forKey: id)
        let tasks = sessionTasks.removeValue(forKey: id)
        notifyStatusChange()
        return (session, tasks)
    }

    func takeAllForStop() -> ((any ITcpServer)?, [Task<Void, Never>], [any ITcpSession]) {
        let sTasks = serverTasks
        serverTasks.removeAll()
        let srv = server
        server = nil
        let sessions = Array(activeSessions.values)
        sessionTasks.values.flatMap { $0 }.forEach { $0.cancel() }
        activeSessions.removeAll()
        sessionTasks.removeAll()
        
        isStarted = false
        isTransferring = false
        isListening = false
        notifyStatusChange()
        
        return (srv, sTasks, sessions)
    }

    func getSessions() -> [any ITcpSession] {
        return Array(activeSessions.values)
    }
}
