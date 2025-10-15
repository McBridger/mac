import Foundation
import OSLog

// MARK: - Message Protocol Structs

public enum MessageType: Int, Codable, Sendable {
    case CLIPBOARD = 0
    case DEVICE_NAME = 1
}

// Внутренняя структура для кодирования/декодирования по BLE
// Соответствует TransferMessage из Java-примера
struct TransferMessage: Codable {
    let t: Int // type
    let p: String // payload
}

public struct BridgerMessage: Codable, Sendable {
    public let type: MessageType
    public let value: String
    public let address: String?
    public let id: UUID
    public let timestamp: Date
    
    // Инициализатор для создания сообщения для отправки
    public init(type: MessageType, value: String, address: String? = nil, id: UUID = UUID(), timestamp: Date = Date()) {
        self.type = type
        self.value = value
        self.address = address
        self.id = id
        self.timestamp = timestamp
    }
    
    public func toData() -> Data? {
        let transferMessage = TransferMessage(t: self.type.rawValue, p: self.value)
        let encoder = JSONEncoder()
        
        do {
            return try encoder.encode(transferMessage)
        } catch {
            Logger.coreModels.error("Failed to encode BridgerMessage: \(error.localizedDescription)")
            return nil
        }
    }
    
    // Статический метод для создания BridgerMessage из полученных BLE Data
    public static func fromData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        let decoder = JSONDecoder()
        let transferMessage = try decoder.decode(TransferMessage.self, from: data)
        
        guard let messageType = MessageType(rawValue: transferMessage.t) else {
            throw BridgerMessageError.unknownMessageType
        }
        
        return BridgerMessage(type: messageType, value: transferMessage.p, address: address)
    }
}

enum BridgerMessageError: Error, LocalizedError {
    case unknownMessageType
    
    var errorDescription: String? {
        switch self {
        case .unknownMessageType:
            return "Unknown message type received."
        }
    }
}

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let coreModels = Logger(subsystem: subsystem, category: "CoreModels")
}