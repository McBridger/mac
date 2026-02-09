#if DEBUG
@preconcurrency import Combine
import Foundation

final class MockTcpManager: TcpManaging, @unchecked Sendable {
    let messages = PassthroughSubject<BridgerMessage, Never>()
    let state = CurrentValueSubject<TcpConnectionState, Never>(.idle)

    func start(port: Int) async throws {
        print("Mock TCP Manager: Started listening on port \(port)")
        state.send(.listening(port: port))
    }

    func stop() async {
        print("Mock TCP Manager: Stopped")
        state.send(.idle)
    }

    func send(_ message: BridgerMessage) async throws {
        print("Mock TCP Manager: Sending message \(message.id)")
    }

    func sendBlob(_ message: BridgerMessage, url: URL, to host: String, port: Int) async throws {
        print("Mock TCP Manager: Sending blob \(message.id) to \(host):\(port)")
        // Simulate successful transfer
        DistributedNotificationCenter.default().postNotificationName(
            TestNotification.dataSent.name,
            object: "MOCK_TCP_BLOB_SENT",
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
#endif
