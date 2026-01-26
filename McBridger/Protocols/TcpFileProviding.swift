import Foundation

public protocol TcpFileProviding: Sendable {
    func registerFile(at url: URL) async -> String
    func getFileURL(id: String) async -> URL?
    func cleanup() async
}
