import Foundation

public enum TransportError: Error {
    case notConnected
    case resourceBusy
    case timedOut
}

public enum SessionState: Sendable {
    case connecting
    case connected
    case disconnected
    case error
}

public enum TransportState: Sendable {
    case idle
    case ready
    case connected
    case transferring
}

public protocol ITcpSession: AnyObject, Sendable {
    var id: String { get }
    var host: String { get }
    var port: Int { get }
    
    var stateUpdates: AsyncStream<SessionState> { get }
    var incomingMessages: AsyncStream<Data> { get }
    
    func send(_ data: Data) async throws
    func forcePing() async throws
    func setPingEnabled(_ enabled: Bool) async
    func disconnect() async
}

public typealias TcpConnectionFactory = @Sendable (String, Int) async throws -> any ITcpSession

public enum ServerState: Sendable {
    case stopped
    case starting
    case listening
    case error
}

public protocol ITcpServer: Sendable {
    var stateUpdates: AsyncStream<ServerState> { get }
    var newSessions: AsyncStream<any ITcpSession> { get }
    var isListening: Bool { get async }
    func stop() async
}

// Factory that creates and starts a server on the given port.
// TcpTransport uses this to create a new server instance on each start().
public typealias TcpServerFactory = @Sendable (_ port: Int) async throws -> any ITcpServer
