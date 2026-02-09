import Foundation
import Combine

public enum TcpConnectionState: Sendable {
    case idle
    case listening(port: Int)
    case connected(remoteAddress: String)
    case error(String)
}

public protocol TcpManaging: AnyObject, Sendable {
    var state: CurrentValueSubject<TcpConnectionState, Never> { get }
    var messages: PassthroughSubject<BridgerMessage, Never> { get }
    
    func start(port: Int) async throws
    func stop() async
    func send(_ message: BridgerMessage) async throws
    func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws
}