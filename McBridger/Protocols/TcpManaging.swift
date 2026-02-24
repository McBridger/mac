import Foundation
import Combine

public enum TcpState: Equatable, Sendable {
    case idle
    case ready
    case connected(remoteAddress: String)
    case transferring(progress: Double)
    case error(String)
}

public protocol TcpManaging: AnyObject, Sendable {
    var state: CurrentValueSubject<TcpState, Never> { get }
    var messages: PassthroughSubject<BridgerMessage, Never> { get }
    
    func start(port: Int) async throws
    func stop() async
    func disconnect() async
    func forcePing() async throws
    func send(_ message: BridgerMessage) async throws
    func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws
}