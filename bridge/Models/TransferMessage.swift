import Foundation

/// Internal DTO for over-the-air transmission.
/// Shared between the main app and UI tests to ensure type-safe communication.
public struct TransferMessage: Codable {
    public let t: Int     // type (MessageType)
    public let p: String  // payload
    public let ts: Double // timestamp

    public init(t: Int, p: String, ts: Double) {
        self.t = t
        self.p = p
        self.ts = ts
    }
}
