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

    private func simulateIntroduction(id: UUID) {
        let introMessage = TransferMessage(
            t: 1, // DEVICE_NAME
            p: "Pixel 7 Pro (Mock)",
            ts: Date().timeIntervalSince1970
        )
        if let data = try? JSONEncoder().encode(introMessage) {
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