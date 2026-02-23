import Foundation
import Combine
import OSLog

public actor HistoryManager: HistoryManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Core", category: "History")
    
    nonisolated public let items = CurrentValueSubject<[Porter], Never>([])
    
    private let historyURL: URL = {
        let paths = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = paths[0].appendingPathComponent("McBridger", isDirectory: true)
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        return appSupport.appendingPathComponent("history.json")
    }()

    public init() {
        // Since it's an actor, we need a task to load history during init
        Task {
            await loadHistory()
        }
    }
    
    public func addOrUpdate(_ porter: Porter) async {
        var current = items.value
        if let index = current.firstIndex(where: { $0.id == porter.id }) {
            current[index] = porter
        } else {
            current.insert(porter, at: 0)
            if current.count > 50 { 
                current.removeLast()
            }
        }
        items.send(current)
        saveHistory()
    }
    
    public func clear() async {
        items.send([])
        try? FileManager.default.removeItem(at: historyURL)
    }
    
    private func loadHistory() {
        guard FileManager.default.fileExists(atPath: historyURL.path) else { return }
        
        do {
            let data = try Data(contentsOf: historyURL)
            let decoded = try JSONDecoder().decode([Porter].self, from: data)
            items.send(decoded)
            logger.info("Loaded \(decoded.count) items from history.")
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
    
    private func saveHistory() {
        do {
            let data = try JSONEncoder().encode(items.value)
            try data.write(to: historyURL, options: .atomic)
        } catch {
            logger.error("Failed to save history: \(error.localizedDescription)")
        }
    }
}
