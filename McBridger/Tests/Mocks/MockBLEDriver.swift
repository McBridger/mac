#if DEBUG
import Foundation
import Combine

public final class MockBLEDriver: BLEDriverProtocol, @unchecked Sendable {
    private let continuation: AsyncStream<BLEDriverEvent>.Continuation
    public let eventStream: AsyncStream<BLEDriverEvent>
    
    public init() {
        var c: AsyncStream<BLEDriverEvent>.Continuation!
        self.eventStream = AsyncStream { c = $0 }
        self.continuation = c
        
        setupNotificationObservers()
        
        // Initial hardware state simulation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            self.simulatePowerOn()
        }
    }
    
    private func simulatePowerOn() {
        self.continuation.yield(.didUpdateState(.poweredOn))
    }
    
    private func setupNotificationObservers() {
        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.connectDevice.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let id = self.requireID(from: notification)
            self.continuation.yield(.didSubscribe(central: id))
        }

        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.introduceDevice.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let id = self.requireID(from: notification)
            self.simulateIntroduction(id: id)
        }

        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.connectAndIntroduceDevice.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let id = self.requireID(from: notification)
            self.continuation.yield(.didSubscribe(central: id))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                self.simulateIntroduction(id: id)
            }
        }

        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.simulateIncomingTiny.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let id = self.requireID(from: notification)
            let text = self.requirePayloadString(from: notification)
            self.simulateIncomingTiny(id: id, text: text)
        }
        
        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.receiveData.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let self = self else { return }
            let id = self.requireID(from: notification)
            let payload = self.requirePayload(from: notification)
            self.continuation.yield(.didReceiveData(payload, from: id))
        }
    }

    private func requireID(from notification: Notification) -> UUID {
        guard let dict = notification.testPayload,
              let idString = dict["id"] as? String,
              let id = UUID(uuidString: idString) else {
            preconditionFailure("❌ MockBLEDriver: Notification missing valid 'id' in JSON payload. Got: \(String(describing: notification.object))")
        }
        return id
    }

    private func requirePayload(from notification: Notification) -> Data {
        guard let dict = notification.testPayload,
              let payloadHex = dict["payload"] as? String,
              let payload = Data(hexString: payloadHex) else {
            preconditionFailure("❌ MockBLEDriver: Notification missing valid 'payload' (hex) in JSON payload. Got: \(String(describing: notification.object))")
        }
        return payload
    }

    private func requirePayloadString(from notification: Notification) -> String {
        guard let dict = notification.testPayload,
              let payload = dict["payload"] as? String else {
            preconditionFailure("❌ MockBLEDriver: Notification missing 'payload' string in JSON payload.")
        }
        return payload
    }

    private func simulateIncomingTiny(id: UUID, text: String) {
        let message = BridgerMessage(content: .tiny(text: text))
        if let data = message.toData() {
            self.continuation.yield(.didReceiveData(data, from: id))
        }
    }

    private func simulateIntroduction(id: UUID) {
        let introMessage = BridgerMessage(
            content: .intro(deviceName: "Pixel 7 Pro (Mock)", ip: "192.168.1.100", port: 41492),
            id: id.uuidString
        )
        if let data = introMessage.toData() {
            self.continuation.yield(.didReceiveData(data, from: id))
        }
    }

    public func advertise(_ config: BLEConfig) {
        continuation.yield(.isAdvertising(true))
        continuation.yield(.didAddService(nil))
    }

    public func stop() {
        continuation.yield(.isAdvertising(false))
    }

    public func send(_ data: Data, to targetUUIDs: [UUID]) -> Bool {
        DistributedNotificationCenter.default().postNotificationName(
            TestNotification.dataSent.name,
            object: data.hexString,
            userInfo: nil,
            deliverImmediately: true
        )
        return true
    }
    
    public func simulatePowerState(_ status: BLEStatus) {
        continuation.yield(.didUpdateState(status))
    }
}
#endif
