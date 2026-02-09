import Foundation

/// Internal DTOs for over-the-air transmission.
/// Shared between the main app and UI tests to ensure type-safe communication.

public enum BridgerMessageType: Int, Codable, Sendable {
    case tiny = 0
    case intro = 1
    case blob = 2
    case chunk = 3
}

public enum BlobType: String, Codable {
    case file = "FILE"
    case text = "TEXT"
    case image = "IMAGE"
}
