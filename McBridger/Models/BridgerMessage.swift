import Foundation
import OSLog

public enum MessageContent {
    case clipboard(text: String)
    case intro(deviceName: String)
    case file(url: String, name: String, size: String)

    var type: MessageType {
        switch self {
        case .clipboard: return .clipboard
        case .intro: return .intro
        case .file: return .file
        }
    }
}

public struct Message: Identifiable {
    public let id: String
    public let timestamp: Double
    public var address: String?
    public let content: MessageContent

    public init(
        content: MessageContent,
        address: String? = nil,
        id: String = UUID().uuidString,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.content = content
        self.address = address
        self.id = id
        self.timestamp = timestamp
    }
}

extension Message {
    public func toData() throws -> Data {
        let encoder = JSONEncoder()
        
        switch content {
        case .clipboard(let text):
            let dto = ClipboardDto(id: id, ts: timestamp, a: address, p: text)
            return try encoder.encode(dto)
            
        case .intro(let deviceName):
            let dto = IntroDto(id: id, ts: timestamp, a: address, p: deviceName)
            return try encoder.encode(dto)
            
        case .file(let url, let name, let size):
            let dto = FileDto(id: id, ts: timestamp, a: address, u: url, n: name, s: size)
            return try encoder.encode(dto)
        }
    }

    public static func fromData(_ data: Data) throws -> Message {
        let decoder = JSONDecoder()

        let header: BaseMessageDto
        do {
            header = try decoder.decode(BaseMessageDto.self, from: data)
        } catch {
            let rawJson = String(data: data, encoding: .utf8) ?? "Non-UTF8"
            Logger.coreModels.error("Decoding error: \(error.localizedDescription). Data: \(rawJson)")
            throw MessageError.unknownMessageType
        }

        let now = Date().timeIntervalSince1970
        if abs(now - header.ts) > 60 {
            Logger.coreModels.warning("Expired message rejected: \(header.id)")
            throw MessageError.expiredMessage
        }
        
        switch header.t {
        case .clipboard:
            let dto = try decoder.decode(ClipboardDto.self, from: data)
            return Message(
                content: .clipboard(text: dto.p),
                address: dto.a,
                id: dto.id,
                timestamp: dto.ts
            )
            
        case .intro:
            let dto = try decoder.decode(IntroDto.self, from: data)
            return Message(
                content: .intro(deviceName: dto.p),
                address: dto.a,
                id: dto.id,
                timestamp: dto.ts
            )
            
        case .file:
            let dto = try decoder.decode(FileDto.self, from: data)
            return Message(
                content: .file(url: dto.u, name: dto.n, size: dto.s),
                address: dto.a,
                id: dto.id,
                timestamp: dto.ts
            )

        default:
            throw MessageError.unknownMessageType
        }
    }
}

public enum MessageError: Error, LocalizedError {
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
