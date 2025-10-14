import AppKit
import Foundation
import CoreModels

@MainActor
public class ClipboardManager {
    private let pasteboard: NSPasteboard
    private let pollingInterval: TimeInterval
    private var lastChangeCount: Int
    
    private var monitoringTask: Task<Void, Never>?

    public let stream: AsyncStream<BridgerMessage>
    private let continuation: AsyncStream<BridgerMessage>.Continuation

    public init(pasteboard: NSPasteboard = .general, pollingInterval: TimeInterval = 1.0) {
        self.pasteboard = pasteboard
        self.pollingInterval = pollingInterval
        self.lastChangeCount = pasteboard.changeCount

        (self.stream, self.continuation) = AsyncStream.makeStream()
    }
    
    deinit {
        monitoringTask?.cancel()
    }
    
    public func setText(_ text: String) {
        if pasteboard.string(forType: .string) == text {
            return
        }
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        self.lastChangeCount = pasteboard.changeCount
    }
    
    public func start() {
        monitoringTask?.cancel()
        monitoringTask = nil
        
        monitoringTask = Task {
            while !Task.isCancelled {
                checkPasteboard()
                do {
                    try await Task.sleep(nanoseconds: UInt64(pollingInterval * 1_000_000_000))
                } catch {
                    break
                }
            }
        }
    }
    
    private func checkPasteboard() {
        guard pasteboard.changeCount != lastChangeCount else { return }
        
        lastChangeCount = pasteboard.changeCount

        if let newText = pasteboard.string(forType: .string) {
            let message = BridgerMessage(type: .CLIPBOARD, value: newText)
            continuation.yield(message)
        }
    }
}