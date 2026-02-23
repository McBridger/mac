import Foundation

/// Internal DTOs for over-the-air transmission.
/// Shared between the main app and UI tests to ensure type-safe communication.

public enum BridgerMessageType: Int, Codable, Sendable {
    case tiny = 0
    case intro = 1
    case blob = 2
    case chunk = 3
    case ping = 4
}

public enum EncryptionState: String, Codable, Sendable, Equatable {
    case idle = "IDLE"
    case encrypting = "ENCRYPTING"
    case keysReady = "KEYS_READY"
    case error = "ERROR"
}
