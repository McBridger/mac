import Foundation
import OSLog

public enum BridgerMessageContent {
    case clipboard(text: String)
    case intro(deviceName: String)
    case file(url: String, name: String, size: String)
    
    public var text: String? {
        if case .clipboard(let text) = self { return text }
        return nil
    }
    
    public var device: String? {
        if case .intro(let name) = self { return name }
        return nil
    }
    
    public var file: (url: String, name: String, size: String)? {
        if case .file(let url, let name, let size) = self { return (url, name, size) }
        return nil
    }
}

public struct BridgerMessage: Identifiable {
    public let id: String
    public let timestamp: Double
    public var address: String?
    public let content: BridgerMessageContent

    public init(
        content: BridgerMessageContent,
        address: String? = nil,
        id: String = UUID().uuidString,
        timestamp: Double = Date().timeIntervalSince1970
    ) {
        self.content = content
        self.address = address
        self.id = id
        self.timestamp = timestamp
    }
    
    public var type: BridgerMessageType {
        switch self.content {
            case .clipboard: return .clipboard
            case .intro: return .intro
            case .file: return .file
        }
    }
}

extension BridgerMessage {
    public func toData() -> Data? {
        let encoder = JSONEncoder()
        
        do {
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
        } catch {
            Logger.coreModels.error("Decoding error: \(error.localizedDescription). Type: \(self.type.rawValue)")
            return nil
        }
    }

    public static func fromData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        let decoder = JSONDecoder()

        let header: BaseBridgerMessageDto
        do {
            header = try decoder.decode(BaseBridgerMessageDto.self, from: data)
        } catch {
            let rawJson = String(data: data, encoding: .utf8) ?? "Non-UTF8"
            Logger.coreModels.error("Decoding error: \(error.localizedDescription). Data: \(rawJson)")
            throw BridgerMessageError.unknownType
        }

        let now = Date().timeIntervalSince1970
        if abs(now - header.ts) > 60 {
            Logger.coreModels.warning("Expired message rejected: \(header.id)")
            throw BridgerMessageError.expired
        }
        
        switch header.t {
        case .clipboard:
            let dto = try decoder.decode(ClipboardDto.self, from: data)
            return BridgerMessage(
                content: .clipboard(text: dto.p),
                address: address ?? dto.a,
                id: dto.id,
                timestamp: dto.ts
            )
            
        case .intro:
            let dto = try decoder.decode(IntroDto.self, from: data)
            return BridgerMessage(
                content: .intro(deviceName: dto.p),
                address: address ?? dto.a,
                id: dto.id,
                timestamp: dto.ts
            )
            
        case .file:
            let dto = try decoder.decode(FileDto.self, from: data)
            return BridgerMessage(
                content: .file(url: dto.u, name: dto.n, size: dto.s),
                address: address ?? dto.a,
                id: dto.id,
                timestamp: dto.ts
            )
        }
    }
}

public enum BridgerMessageError: Error, LocalizedError {
    case unknownType
    case expired
    case decryptionFailed

    public var errorDescription: String? {
        switch self {
        case .unknownType:
            return "Unknown message type received."
        case .expired:
            return "BridgerMessage is too old or from the future. Possible replay attack."
        case .decryptionFailed:
            return "Failed to decrypt message. Wrong key or corrupt data."
        }
    }
}

extension Logger {
    private static let subsystem = "com.mcbridger.Model"
    static let coreModels = Logger(subsystem: subsystem, category: "Transfer")
}
