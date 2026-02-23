import Foundation
import OSLog
import Factory

public actor BlobStorageManager: BlobStorageManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Services", category: "BlobStorage")
    
    private struct PendingBlob {
        let name: String
        let size: Int64
        let type: BlobType
        let fileHandle: FileHandle
        let path: URL
        var bytesReceived: Int64
    }
    
    private var pendingBlobs: [String: PendingBlob] = [:]
    
    private let downloadsURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("McBridger", isDirectory: true)
    }()
    
    public init() {
        try? FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
    }
    
    public func registerBlob(id: String, name: String, size: Int64, type: BlobType) async throws {
        let fileURL = downloadsURL.appendingPathComponent(name)
        
        if pendingBlobs[id] != nil {
            logger.info("Blob \(id) already registered, skipping duplicate registration.")
            return
        }
        
        try FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
        
        if FileManager.default.fileExists(atPath: fileURL.path) {
            try FileManager.default.removeItem(at: fileURL)
        }
        
        if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
            throw NSError(domain: "BlobStorageManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to create file at \(fileURL.path)"])
        }
        
        let handle = try FileHandle(forWritingTo: fileURL)
        try handle.truncate(atOffset: UInt64(size))
        
        pendingBlobs[id] = PendingBlob(
            name: name,
            size: size,
            type: type,
            fileHandle: handle,
            path: fileURL,
            bytesReceived: 0
        )
        
        logger.info("Registered blob: \(name) (\(size) bytes) at \(fileURL.path)")
    }
    
    public func handleChunk(id: String, offset: Int64, data: Data) async throws -> Bool {
        guard var blob = pendingBlobs[id] else {
            logger.warning("Received chunk for unknown blob: \(id)")
            return false
        }
        
        try blob.fileHandle.seek(toOffset: UInt64(offset))
        try blob.fileHandle.write(contentsOf: data)
        
        blob.bytesReceived += Int64(data.count)
        pendingBlobs[id] = blob
        
        return blob.bytesReceived >= blob.size
    }
    
    public func finalizeBlob(id: String) async throws -> URL {
        guard let blob = pendingBlobs[id] else {
            throw NSError(domain: "BlobStorageManager", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot finalize unknown blob: \(id)"])
        }
        try blob.fileHandle.close()
        pendingBlobs.removeValue(forKey: id)
        logger.info("Successfully assembled blob: \(blob.name)")
        return blob.path
    }
    
    public func createTempFile(for text: String, id: String) async throws -> URL {
        let tempURL = downloadsURL.appendingPathComponent("\(id).txt")
        try text.write(to: tempURL, atomically: true, encoding: .utf8)
        return tempURL
    }
}
