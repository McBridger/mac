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

        DistributedNotificationCenter.default().addObserver(
            forName: TestNotification.simulateFileCopy.name,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let urlString = notification.object as? String,
                  let url = URL(string: urlString) else { return }
            
            // Simulate reading file size for the blob message
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
            let size = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
            
            let message = BridgerMessage(
                content: .blob(name: url.lastPathComponent, size: size, blobType: .file),
                address: url.absoluteString
            )
            self?.update.send(message)
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
        // Notify tests that file was set on clipboard
        DistributedNotificationCenter.default().postNotificationName(
            TestNotification.fileSetLocally.name,
            object: url.absoluteString,
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
#endif
