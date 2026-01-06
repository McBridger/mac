#if DEBUG
import Foundation

public final class MockAppConfig: AppConfiguring {
    public let advertiseID: String = "93191b22-c437-4348-b10f-f522e69f289c"
    public let serviceID: String = "7569273b-b3e3-4672-867d-b07fc54be79f"
    public let characteristicID: String = "bf13657b-b172-44f2-8c11-1b25a521a28a"
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
