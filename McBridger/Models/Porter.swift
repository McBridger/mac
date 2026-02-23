import Foundation

public enum BlobType: String, Codable, Sendable {
    case file = "FILE"
    case text = "TEXT"
    case image = "IMAGE"
}

public struct Porter: Identifiable, Codable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending = "PENDING"
        case active = "ACTIVE"
        case completed = "COMPLETED"
        case error = "ERROR"
    }

    public let id: String
    public let timestamp: Double
    public let isOutgoing: Bool
    public var status: Status
    public var error: String?
    public var name: String
    public var type: BlobType
    public let totalSize: Int64
    public var progress: Double
    public var currentSize: Int64
    public var speedBps: Int64
    public var data: String?

    public init(
        id: String = UUID().uuidString,
        timestamp: Double = Date().timeIntervalSince1970,
        isOutgoing: Bool,
        status: Status = .pending,
        error: String? = nil,
        name: String,
        type: BlobType,
        totalSize: Int64,
        progress: Double = 0,
        currentSize: Int64 = 0,
        speedBps: Int64 = 0,
        data: String? = nil
    ) {
        self.id = id
        self.timestamp = timestamp
        self.isOutgoing = isOutgoing
        self.status = status
        self.error = error
        self.name = name
        self.type = type
        self.totalSize = totalSize
        self.progress = progress
        self.currentSize = currentSize
        self.speedBps = speedBps
        self.data = data
    }
}
