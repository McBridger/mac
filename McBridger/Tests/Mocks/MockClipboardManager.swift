#if DEBUG
import Combine
import Foundation

class MockClipboardManager: ClipboardManaging {
    let update = PassthroughSubject<BridgerMessage, Never>()

    public init() {
        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.simulateClipboardChange.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let text = notification.object as? String else { return }
            self?.update.send(BridgerMessage(content: .tiny(text: text)))
        }
    }

    func setText(_ text: String) {
        print("Mock Clipboard Set: \(text)")
        // Notify tests that clipboard was updated from remote
        DistributedNotificationCenter.default().postNotificationName(
            TestNotification.clipboardSetLocally.name,
            object: text,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func setFile(url: URL) {
        print("Mock Clipboard Set File: \(url.lastPathComponent)")
    }
}
#endif
