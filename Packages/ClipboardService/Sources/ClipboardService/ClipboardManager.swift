import AppKit
import Combine
import Foundation

@MainActor
public class ClipboardManager: ObservableObject {
    // Using a publisher instead of a delegate. Anyone can subscribe.
    @Published var currentText: String = ""

    private var pasteboard: NSPasteboard
    private var timer: Timer?
    private var cancellable: AnyCancellable?
    private var lastChangeCount: Int

    // Dependency injection to allow mocking for tests.
    public init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
        self.lastChangeCount = pasteboard.changeCount
        // Read the initial content of the clipboard on startup
        if let initialText = pasteboard.string(forType: .string) {
            self.currentText = initialText
        }
        start()
    }

    /// Puts new text into the clipboard.
    /// This method is the single source of truth for changing the clipboard from our code.
    func copy(text: String) {
        // If the text is the same, do nothing.
        guard text != currentText else { return }

        // Update the pasteboard.
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Update our internal state.
        // `@Published` will notify all subscribers that the text has changed.
        self.currentText = text
        self.lastChangeCount = pasteboard.changeCount
    }

    /// Starts monitoring the clipboard.
    private func start() {
        // A timer is still the most reliable way for AppKit, unfortunately.
        // Notifications and KVO for NSPasteboard are unreliable.
        self.cancellable = Timer.publish(every: 1.0, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.checkPasteboard()
            }
    }

    /// Stops monitoring the clipboard.
    public func stop() {
        cancellable?.cancel()
    }

    /// Checks if something has been put into the clipboard from outside our app.
    private func checkPasteboard() {
        // If the change count hasn't changed, we're good.
        guard pasteboard.changeCount != lastChangeCount else { return }

        // The change count has changed! Let's update.
        lastChangeCount = pasteboard.changeCount

        // Get the new text. If it's not text (e.g., files, images),
        // we'll get nil and do nothing.
        if let newText = pasteboard.string(forType: .string), newText != currentText {
            // Update our publisher, and all subscribers will be notified immediately.
            self.currentText = newText
        }
    }
}
