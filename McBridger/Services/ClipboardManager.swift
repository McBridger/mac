import AppKit
import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.mcbridger.Service", category: "Clipboard")

public class ClipboardManager: ClipboardManaging {
    // MARK: - Public Publisher

    public let update = PassthroughSubject<BridgerMessage, Never>()

    // MARK: - Private Properties

    private let pasteboard: NSPasteboard
    private let pollingInterval: TimeInterval
    private var lastChangeCount: Int
    private var timerCancellable: AnyCancellable?

    // MARK: - Initialization

    public init(pasteboard: NSPasteboard = .general, pollingInterval: TimeInterval = 1.0) {
        self.pasteboard = pasteboard
        self.pollingInterval = pollingInterval
        self.lastChangeCount = pasteboard.changeCount

        logger.info("ClipboardManager initialized. Starting monitoring...")

        self.timerCancellable =
            Timer
            .publish(every: pollingInterval, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPasteboard()
            }
    }

    deinit {
        timerCancellable?.cancel()
        logger.info("ClipboardManager deinitialized")
    }

    // MARK: - Public API

    public func setText(_ text: String) {
        if pasteboard.string(forType: .string) == text {
            logger.debug("Attempted to set the same text. Ignoring.")
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastChangeCount = pasteboard.changeCount
        logger.info("Set new text to pasteboard.")
    }

    public func setFile(url: URL) {
        pasteboard.clearContents()
        pasteboard.writeObjects([url as NSURL])
        self.lastChangeCount = pasteboard.changeCount
        logger.info("Set file URL to pasteboard: \(url.lastPathComponent)")
    }

    // MARK: - Private Methods

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            // logger.trace("No changes in pasteboard.") // This is too noisy, uncomment for deep debugging
            return
        }

        logger.debug("Pasteboard change detected. New changeCount: \(self.pasteboard.changeCount)")
        lastChangeCount = pasteboard.changeCount

        // 1. Check for Files first (NSURL)
        if let url = pasteboard.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL, url.isFileURL {
            logger.info("New file found in pasteboard: \(url.lastPathComponent). Sending blob announcement.")
            
            do {
                let resources = try url.resourceValues(forKeys: [.fileSizeKey])
                let size = Int64(resources.fileSize ?? 0)
                
                // Use file path as 'address' for internal routing in AppLogic
                let message = BridgerMessage(
                    content: .blob(name: url.lastPathComponent, size: size, blobType: .file),
                    address: url.absoluteString
                )
                update.send(message)
                return
            } catch {
                logger.error("Failed to read file attributes for \(url.path): \(error.localizedDescription)")
            }
        } 
        
        // 2. Fallback to Text
        if let newText = pasteboard.string(forType: .string) {
            logger.info("New text found in pasteboard. Sending message.")
            update.send(BridgerMessage(content: .tiny(text: newText)))
        } else {
            logger.warning("Pasteboard changed, but no supported content found.")
        }
    }
}
