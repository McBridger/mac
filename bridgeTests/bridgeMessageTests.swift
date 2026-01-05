import XCTest
@testable import bridge

final class bridgeMessageTests: XCTestCase {

    func testMessageSerialization() throws {
        let originalValue = "Hello, Bridger!"
        let message = BridgerMessage(type: .CLIPBOARD, value: originalValue)
        
        // 1. Serialize to Data
        guard let data = message.toData() else {
            XCTFail("Failed to serialize message")
            return
        }
        
        // 2. Deserialize back
        let decoded = try BridgerMessage.fromData(data)
        
        XCTAssertEqual(decoded.value, originalValue)
        XCTAssertEqual(decoded.type, .CLIPBOARD)
    }

    func testReplayProtection() throws {
        // Create a message from the "future" (invalid)
        let futureDate = Date().addingTimeInterval(120) // +2 minutes
        let transferMessage = TransferMessage(
            t: MessageType.CLIPBOARD.rawValue,
            p: "Old Data",
            ts: futureDate.timeIntervalSince1970
        )
        
        let data = try JSONEncoder().encode(transferMessage)
        
        // Should throw .expiredMessage
        XCTAssertThrowsError(try BridgerMessage.fromData(data)) { error in
            XCTAssertEqual(error as? BridgerMessageError, .expiredMessage)
        }
    }
    
    func testInvalidMessageTypes() throws {
        let invalidData = "{\"t\": 99, \"p\": \"test\", \"ts\": \(Date().timeIntervalSince1970)}".data(using: .utf8)!
        
        XCTAssertThrowsError(try BridgerMessage.fromData(invalidData)) { error in
            XCTAssertEqual(error as? BridgerMessageError, .unknownMessageType)
        }
    }
}
