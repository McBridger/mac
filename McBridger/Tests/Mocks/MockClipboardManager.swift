#if DEBUG
import Combine
import Foundation

class MockClipboardManager: ClipboardManaging {
    let update = PassthroughSubject<BridgerMessage, Never>()

    public init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(TestNotification.simulateClipboardChange),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String else { return }
            self?.update.send(BridgerMessage(type: .CLIPBOARD, value: text))
        }
    }

    func setText(_ text: String) {
        print("Mock Clipboard Set: \(text)")
        // Notify tests that clipboard was updated from remote
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.clipboardSetLocally),
            object: text,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
#endif
