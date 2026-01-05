import Foundation
import OSLog

public enum MessageType: Int, Codable, Sendable {
    case CLIPBOARD = 0
    case DEVICE_NAME = 1
}

/// Internal DTO for over-the-air transmission
struct TransferMessage: Codable {
    let t: Int      // type
    let p: String   // payload
    let ts: Double  // timestamp
}

public struct BridgerMessage: Codable, Sendable {
    public let type: MessageType
    public let value: String
    public let address: String?
    public let id: UUID
    public let timestamp: Date

    public init(
        type: MessageType, value: String, address: String? = nil, id: UUID = UUID(),
        timestamp: Date = Date()
    ) {
        self.type = type
        self.value = value
        self.address = address
        self.id = id
        self.timestamp = timestamp
    }

    /// Converts message to raw JSON data using TransferMessage DTO
    func toData() -> Data? {
        let transferMessage = TransferMessage(
            t: self.type.rawValue,
            p: self.value,
            ts: self.timestamp.timeIntervalSince1970
        )
        do {
            return try JSONEncoder().encode(transferMessage)
        } catch {
            Logger.coreModels.error(
                "Failed to encode BridgerMessage: \(error.localizedDescription)")
            return nil
        }
    }

    /// Creates a BridgerMessage from raw JSON data
    static func fromData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        let decoder = JSONDecoder()
        let transferMessage = try decoder.decode(TransferMessage.self, from: data)

        guard let messageType = MessageType(rawValue: transferMessage.t) else {
            throw BridgerMessageError.unknownMessageType
        }

        // Replay Protection Check (Basic)
        let now = Date().timeIntervalSince1970
        if abs(now - transferMessage.ts) > 60 {
            throw BridgerMessageError.expiredMessage
        }

        return BridgerMessage(
            type: messageType,
            value: transferMessage.p,
            address: address,
            timestamp: Date(timeIntervalSince1970: transferMessage.ts)
        )
    }
}

public enum BridgerMessageError: Error, LocalizedError {
    case unknownMessageType
    case expiredMessage
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .unknownMessageType:
            return "Unknown message type received."
        case .expiredMessage:
            return "Message is too old or from the future. Possible replay attack."
        case .decryptionFailed:
            return "Failed to decrypt message. Wrong key or corrupt data."
        }
    }
}

extension Logger {
    private static let subsystem = "com.mcbridger.Model"
    static let coreModels = Logger(subsystem: subsystem, category: "Transfer")
}
