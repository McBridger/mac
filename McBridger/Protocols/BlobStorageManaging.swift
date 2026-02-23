import Foundation

public protocol BlobStorageManaging: Sendable {
    func handleChunk(id: String, offset: Int64, data: Data) async throws -> Bool
    func registerBlob(id: String, name: String, size: Int64, type: BlobType) async throws
    func createTempFile(for text: String, id: String) async throws -> URL
    func finalizeBlob(id: String) async throws -> URL
}
