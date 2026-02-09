import Foundation
import OSLog

public enum BridgerMessageContent: Sendable {
    case tiny(text: String)
    case intro(deviceName: String, ip: String, port: Int)
    case blob(name: String, size: Int64, blobType: BlobType)
    case chunk(id: String, offset: Int64, data: Data)
    
    public var text: String? {
        if case .tiny(let text) = self { return text }
        return nil
    }
    
    public var device: String? {
        if case .intro(let name, _, _) = self { return name }
        return nil
    }
}

public struct BridgerMessage: Identifiable, Sendable {
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
            case .tiny: return .tiny
            case .intro: return .intro
            case .blob: return .blob
            case .chunk: return .chunk
        }
    }
}

extension BridgerMessage {
    public func toData() -> Data? {
        var data = Data()
        
        // 1. Type ID (1 byte)
        data.append(UInt8(self.type.rawValue))
        
        // 2. UUID (16 bytes)
        guard let uuid = UUID(uuidString: id) else { return nil }
        data.append(uuid.uuidBytes)
        
        // 3. Timestamp (8 bytes)
        data.appendBigEndian(timestamp.bitPattern)
        
        // 4. Payload
        switch content {
        case .tiny(let text):
            data.appendS(text)
            
        case .intro(let deviceName, let ip, let port):
            data.appendS(deviceName)
            data.appendS(ip)
            data.appendBigEndian(Int32(port))
            
        case .blob(let name, let size, let blobType):
            data.appendS(name)
            data.appendBigEndian(size)
            data.appendS(blobType.rawValue)
            
        case .chunk(_, let offset, let chunkData):
            data.appendBigEndian(offset)
            data.append(chunkData)
        }
        
        return data
    }

    public static func fromData(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        var offset = 0
        
        func read<T>(_ type: T.Type) throws -> T {
            let size = MemoryLayout<T>.size
            guard offset + size <= data.count else { throw BridgerMessageError.corruptData }
            let value = data.subdata(in: offset..<offset + size).withUnsafeBytes { $0.load(as: T.self) }
            offset += size
            return value
        }
        
        func readBigEndian<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            return try T(bigEndian: read(T.self))
        }
        
        func readS() throws -> String {
            let length = Int(try readBigEndian(Int32.self))
            guard offset + length <= data.count else { throw BridgerMessageError.corruptData }
            let stringData = data.subdata(in: offset..<offset + length)
            guard let s = String(data: stringData, encoding: .utf8) else { throw BridgerMessageError.corruptData }
            offset += length
            return s
        }
        
        // 1. Type ID
        let typeId = Int(try read(UInt8.self))
        guard let type = BridgerMessageType(rawValue: typeId) else { throw BridgerMessageError.unknownType }
        
        // 2. UUID
        let uuidBytes = try data.subdata(in: offset..<offset + 16)
        offset += 16
        let id = UUID(uuid: uuidBytes.withUnsafeBytes { $0.load(as: uuid_t.self) }).uuidString
        
        // 3. Timestamp
        let tsBits = try readBigEndian(UInt64.self)
        let ts = Double(bitPattern: tsBits)
        
        let now = Date().timeIntervalSince1970
        if type != .chunk && abs(now - ts) > 60 {
            throw BridgerMessageError.expired
        }
        
        // 4. Payload
        let content: BridgerMessageContent
        switch type {
        case .tiny:
            content = .tiny(text: try readS())
        case .intro:
            content = .intro(deviceName: try readS(), ip: try readS(), port: Int(try readBigEndian(Int32.self)))
        case .blob:
            content = .blob(name: try readS(), size: try readBigEndian(Int64.self), blobType: BlobType(rawValue: try readS()) ?? .file)
        case .chunk:
            let chunkOffset = try readBigEndian(Int64.self)
            let chunkData = data.subdata(in: offset..<data.count)
            content = .chunk(id: id, offset: chunkOffset, data: chunkData)
        }
        
        return BridgerMessage(content: content, address: address, id: id, timestamp: ts)
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var val = value.bigEndian
        Swift.withUnsafeBytes(of: &val) { append(contentsOf: $0) }
    }
    
    mutating func appendS(_ s: String) {
        let sd = s.data(using: .utf8) ?? Data()
        appendBigEndian(Int32(sd.count))
        append(sd)
    }
}

private extension UUID {
    var uuidBytes: Data {
        var bytes = uuid_t(0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0)
        withUnsafeMutableBytes(of: &bytes) { uuid_set_bytes(self, $0.baseAddress) }
        return Data(bytes: &bytes, count: 16)
    }
}

private func uuid_set_bytes(_ uuid: UUID, _ bytes: UnsafeMutableRawPointer?) {
    withUnsafeBytes(of: uuid.uuid) {
        memcpy(bytes, $0.baseAddress, 16)
    }
}

public enum BridgerMessageError: Error, LocalizedError {
    case unknownType
    case expired
    case decryptionFailed
    case corruptData

    public var errorDescription: String? {
        switch self {
        case .unknownType:
            return "Unknown message type received."
        case .expired:
            return "BridgerMessage is too old or from the future. Possible replay attack."
        case .decryptionFailed:
            return "Failed to decrypt message. Wrong key or corrupt data."
        case .corruptData:
            return "Message data is corrupt or incomplete."
        }
    }
}

extension Logger {
    private static let subsystem = "com.mcbridger.Model"
    static let coreModels = Logger(subsystem: subsystem, category: "Transfer")
}
