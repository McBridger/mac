import AppKit
import Combine
import Foundation
import CoreModels

@MainActor
public class ClipboardManager {
    private var pasteboard: NSPasteboard
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var lastChangeCount: Int

    public let messageStream: AsyncStream<BridgerMessage>
    private let messageContinuation: AsyncStream<BridgerMessage>.Continuation

    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        (self.messageStream, self.messageContinuation) = AsyncStream.makeStream()
        start()
    }

    /// Sets the text in the clipboard. Called from AppViewModel.
    public func setText(_ text: String) {
        // Avoid feedback loops by checking if the content is already there.
        if pasteboard.string(forType: .string) == text {
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        // Update our change count so we don't immediately fire an event.
        self.lastChangeCount = pasteboard.changeCount
    }

    private func start() {
        self.cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                Task {
                    await self?.checkPasteboard()
                }
            }
    }

    public func stop() {
        cancellable?.cancel()
    }

    private func checkPasteboard() async {
        guard pasteboard.changeCount != lastChangeCount else { return }
        lastChangeCount = pasteboard.changeCount

        if let newText = pasteboard.string(forType: .string) {
            let message = BridgerMessage(type: .CLIPBOARD, value: newText)
            messageContinuation.yield(message)
        }
    }
}
