#if DEBUG
import Foundation

public final class MockAppConfig: AppConfiguring {
    public let encryptionSalt: String = "6d63627269646765725f73616c745f32303236" // mcbridger_salt_2026
    public let mnemonic: String? = nil
    
    public let mnemonicLength: Int = {
        if let index = ProcessInfo.processInfo.arguments.firstIndex(of: "--mnemonic-length"),
           index + 1 < ProcessInfo.processInfo.arguments.count,
           let length = Int(ProcessInfo.processInfo.arguments[index + 1]) {
            return length
        }
        return 6
    }()

    public init() {}
}
#endif
