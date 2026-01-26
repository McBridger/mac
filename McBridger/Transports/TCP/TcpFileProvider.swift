import Foundation

public actor TcpFileProvider: TcpFileProviding {
    private struct RegisteredFile: Sendable {
        let url: URL
        let createdAt: Date
    }

    private var activeFiles: [String: RegisteredFile] = [:]
    private let fileTTL: TimeInterval = 10 * 60 // 10 minutes

    private var cleanupTask: Task<Void, Never>?

    public init() {
        self.cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 300 * 1_000_000_000) // 5 minutes
                await self?.cleanup()
            }
        }
    }

    deinit {
        cleanupTask?.cancel()
    }

    public func registerFile(at url: URL) async -> String {
        let id = UUID().uuidString
        activeFiles[id] = RegisteredFile(url: url, createdAt: Date())
        return id
    }

    public func getFileURL(id: String) async -> URL? {
        guard let entry = activeFiles[id] else { return nil }
        
        if Date().timeIntervalSince(entry.createdAt) > fileTTL {
            activeFiles.removeValue(forKey: id)
            return nil
        }
        return entry.url
    }

    public func cleanup() async {
        let now = Date()
        activeFiles = activeFiles.filter { 
            now.timeIntervalSince($0.value.createdAt) <= fileTTL 
        }
    }
}
