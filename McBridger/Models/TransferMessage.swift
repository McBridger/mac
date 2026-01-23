import Foundation

/// Internal DTOs for over-the-air transmission.
/// Shared between the main app and UI tests to ensure type-safe communication.

public enum MessageType: Int, Codable, Sendable {
    case clipboard = 0
    case intro = 1
    case file = 2
}

public struct BaseMessageDto: Codable {
    let t: MessageType
    let ts: Double
    let id: String
}

public struct ClipboardDto: Codable {
    var t: MessageType = .clipboard
    let id: String
    let ts: Double
    let a: String?
    let p: String // value
}

public struct IntroDto: Codable {
    var t: MessageType = .intro
    let id: String
    let ts: Double
    let a: String?
    let p: String // value (deviceName)
}

public struct FileDto: Codable {
    var t: MessageType = .file
    let id: String
    let ts: Double
    let a: String?
    let u: String // url
    let n: String // name
    let s: String // size
}