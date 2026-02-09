import XCTest
@testable import McBridgerDev

final class MessageTests: XCTestCase {

    func testMessageSerialization() throws {
        let originalValue = "Hello, Bridger!"
        let message = BridgerMessage(content: .tiny(text: originalValue))
        
        // 1. Serialize to Data
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        // 2. Deserialize back
        let decoded = try BridgerMessage.fromData(data)
        
        XCTAssertEqual(decoded.content.text, originalValue)
        XCTAssertEqual(decoded.type, .tiny)
    }

    func testBlobSerialization() throws {
        let name = "test.txt"
        let size: Int64 = 1024
        let message = BridgerMessage(content: .blob(name: name, size: size, blobType: .file))
        
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        let decoded = try BridgerMessage.fromData(data)
        
        if case .blob(let dName, let dSize, let dType) = decoded.content {
            XCTAssertEqual(dName, name)
            XCTAssertEqual(dSize, size)
            XCTAssertEqual(dType, .file)
        } else {
            XCTFail("Decoded content is not blob")
        }
    }
    
    func testChunkSerialization() throws {
        let id = UUID().uuidString
        let offset: Int64 = 512
        let chunkData = "Chunk context".data(using: .utf8)!
        let message = BridgerMessage(content: .chunk(id: id, offset: offset, data: chunkData), id: id)
        
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        let decoded = try BridgerMessage.fromData(data)
        
        if case .chunk(let dId, let dOffset, let dData) = decoded.content {
            XCTAssertEqual(dId, id)
            XCTAssertEqual(dOffset, offset)
            XCTAssertEqual(dData, chunkData)
        } else {
            XCTFail("Decoded content is not chunk")
        }
    }

    func testReplayProtection() throws {
        // Create a message from the "future" (invalid)
        let futureDate = Date().addingTimeInterval(120) // +2 minutes
        let message = BridgerMessage(content: .tiny(text: "Old Data"), timestamp: futureDate.timeIntervalSince1970)
        
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        // Should throw .expiredMessage
        XCTAssertThrowsError(try BridgerMessage.fromData(data)) { error in
            XCTAssertEqual(error as? BridgerMessageError, .expired)
        }
    }
}
