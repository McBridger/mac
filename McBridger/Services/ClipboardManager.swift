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

    // MARK: - Private Methods

    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else {
            // logger.trace("No changes in pasteboard.") // This is too noisy, uncomment for deep debugging
            return
        }

        logger.debug("Pasteboard change detected. New changeCount: \(self.pasteboard.changeCount)")
        lastChangeCount = pasteboard.changeCount

        if let newText = pasteboard.string(forType: .string) {
            logger.info("New text found in pasteboard. Sending message.")
            update.send(BridgerMessage(type: .CLIPBOARD, value: newText))
        } else {
            logger.warning("Pasteboard changed, but no string content found.")
        }
    }
}
