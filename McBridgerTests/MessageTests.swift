import XCTest
@testable import McBridgerDev

final class MessageTests: XCTestCase {

    func testMessageSerialization() throws {
        let originalValue = "Hello, Bridger!"
        let message = BridgerMessage(content: .clipboard(text: originalValue))
        
        // 1. Serialize to Data
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        // 2. Deserialize back
        let decoded = try BridgerMessage.fromData(data)
        
        XCTAssertEqual(decoded.content.text, originalValue)
        XCTAssertEqual(decoded.type, .clipboard)
    }

    func testReplayProtection() throws {
        // Create a message from the "future" (invalid)
        let futureDate = Date().addingTimeInterval(120) // +2 minutes
        let transferMessage = ClipboardDto(
            t: .clipboard,
            id: UUID().uuidString,
            ts: futureDate.timeIntervalSince1970,
            a: UUID().uuidString,
            p: "Old Data",
        )
        
        let data = try JSONEncoder().encode(transferMessage)
        
        // Should throw .expiredMessage
        XCTAssertThrowsError(try BridgerMessage.fromData(data)) { error in
            XCTAssertEqual(error as? BridgerMessageError, .expired)
        }
    }
    
    func testInvalidMessageTypes() throws {
        let invalidData = "{\"t\": 99, \"p\": \"test\", \"ts\": \(Date().timeIntervalSince1970)}".data(using: .utf8)!
        
        XCTAssertThrowsError(try BridgerMessage.fromData(invalidData)) { error in
            XCTAssertEqual(error as? BridgerMessageError, .unknownType)
        }
    }
}
