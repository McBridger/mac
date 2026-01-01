import Foundation
import OSLog
import CryptoKit
import EncryptionService

// MARK: - Message Protocol Structs

public enum MessageType: Int, Codable, Sendable {
    case CLIPBOARD = 0
    case DEVICE_NAME = 1
}

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
    
    public init(type: MessageType, value: String, address: String? = nil, id: UUID = UUID(), timestamp: Date = Date()) {
        self.type = type
        self.value = value
        self.address = address
        self.id = id
        self.timestamp = timestamp
    }
    
    public func toData() -> Data? {
        let transferMessage = TransferMessage(t: self.type.rawValue, p: self.value, ts: self.timestamp.timeIntervalSince1970)
        let encoder = JSONEncoder()
        
        do {
            return try encoder.encode(transferMessage)
        } catch {
            Logger.coreModels.error("Failed to encode BridgerMessage: \(error.localizedDescription)")
            return nil
        }
    }
    
    /// Encrypts the message data for secure transfer
    public func toEncryptedData() -> Data? {
        guard let data = self.toData() else { return nil }
        guard let keyData = EncryptionService.shared.derive(info: "McBridge_Encryption_Domain", count: 32) else { return nil }
        return BridgerMessage.encrypt(data, key: SymmetricKey(data: keyData))
    }
    
    /// Decrypts and creates a BridgerMessage from encrypted BLE data
    public static func fromEncryptedData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        guard let keyData = EncryptionService.shared.derive(info: "McBridge_Encryption_Domain", count: 32) else {
            throw BridgerMessageError.decryptionFailed
        }
        
        guard let decryptedData = BridgerMessage.decrypt(data, key: SymmetricKey(data: keyData)) else {
            throw BridgerMessageError.decryptionFailed
        }
        
        return try fromData(decryptedData, address: address)
    }

    // Static method to create a BridgerMessage from raw JSON Data
    public static func fromData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        let decoder = JSONDecoder()
        let transferMessage = try decoder.decode(TransferMessage.self, from: data)
        
        guard let messageType = MessageType(rawValue: transferMessage.t) else {
            throw BridgerMessageError.unknownMessageType
        }
        
        // Replay Protection Check
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

    // MARK: - Private Crypto Helpers
    
    private static func encrypt(_ data: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.seal(data, using: key)
            return sealedBox.combined
        } catch {
            Logger.coreModels.error("AES-GCM encryption failed: \(error.localizedDescription)")
            return nil
        }
    }
    
    private static func decrypt(_ combinedData: Data, key: SymmetricKey) -> Data? {
        do {
            let sealedBox = try AES.GCM.SealedBox(combined: combinedData)
            return try AES.GCM.open(sealedBox, using: key)
        } catch {
            Logger.coreModels.error("AES-GCM decryption failed: \(error.localizedDescription)")
            return nil
        }
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
    private static let subsystem = "com.mcbridger.CoreModels"
    static let coreModels = Logger(subsystem: subsystem, category: "CoreModels")
}