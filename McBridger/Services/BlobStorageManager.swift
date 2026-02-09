import Foundation
import OSLog
import Factory

public protocol BlobStorageManaging: Sendable {
    func handleChunk(id: String, offset: Int64, data: Data) async
    func registerBlob(id: String, name: String, size: Int64, type: BlobType) async
}

public final class BlobStorageManager: BlobStorageManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Services", category: "BlobStorage")
    private let queue = DispatchQueue(label: "com.mcbridger.blob-storage-queue")
    
    private struct PendingBlob {
        let name: String
        let size: Int64
        let type: BlobType
        let fileHandle: FileHandle
        let path: URL
        var bytesReceived: Int64 = 0
    }
    
    private var pendingBlobs: [String: PendingBlob] = [:]
    
    private let downloadsURL: URL = {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("McBridger", isDirectory: true)
    }()
    
    public init() {
        try? FileManager.default.createDirectory(at: downloadsURL, withIntermediateDirectories: true)
    }
    
    public func registerBlob(id: String, name: String, size: Int64, type: BlobType) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            let fileURL = self.downloadsURL.appendingPathComponent(name)
            
            if self.pendingBlobs[id] != nil {
                self.logger.info("Blob \(id) already registered, skipping duplicate registration.")
                return
            }
            
            do {
                // Ensure directory exists
                try FileManager.default.createDirectory(at: self.downloadsURL, withIntermediateDirectories: true)
                
                // Create empty file (overwriting if exists)
                if FileManager.default.fileExists(atPath: fileURL.path) {
                    try FileManager.default.removeItem(at: fileURL)
                }
                
                if !FileManager.default.createFile(atPath: fileURL.path, contents: nil) {
                    self.logger.error("FileManager failed to create file at \(fileURL.path)")
                    return
                }
                
                let handle = try FileHandle(forWritingTo: fileURL)
                try handle.truncate(atOffset: UInt64(size))
                
                self.pendingBlobs[id] = PendingBlob(
                    name: name,
                    size: size,
                    type: type,
                    fileHandle: handle,
                    path: fileURL
                )
                
                self.logger.info("Registered blob: \(name) (\(size) bytes) at \(fileURL.path)")
            } catch {
                self.logger.error("Failed to setup file for blob \(name): \(error.localizedDescription)")
            }
        }
    }
    
    public func handleChunk(id: String, offset: Int64, data: Data) async {
        queue.async { [weak self] in
            guard let self = self else { return }
            
            guard var blob = self.pendingBlobs[id] else {
                self.logger.warning("Received chunk for unknown blob: \(id)")
                return
            }
            
            do {
                try blob.fileHandle.seek(toOffset: UInt64(offset))
                try blob.fileHandle.write(contentsOf: data)
                
                blob.bytesReceived += Int64(data.count)
                self.pendingBlobs[id] = blob
                
                if blob.bytesReceived >= blob.size {
                    try blob.fileHandle.close()
                    self.pendingBlobs.removeValue(forKey: id)
                    self.logger.info("Successfully assembled blob: \(blob.name)")
                    
                    // TODO: Notify AppLogic about completion
                    NotificationCenter.default.post(
                        name: .blobDownloadComplete,
                        object: nil,
                        userInfo: ["path": blob.path, "name": blob.name]
                    )
                }
            } catch {
                self.logger.error("Failed to write chunk for \(blob.name): \(error.localizedDescription)")
            }
        }
    }
}

extension NSNotification.Name {
    public static let blobDownloadComplete = NSNotification.Name("com.mcbridger.blob.complete")
}
