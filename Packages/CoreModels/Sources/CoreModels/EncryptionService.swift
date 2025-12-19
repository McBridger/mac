import Foundation
import CryptoKit
import CommonCrypto
import OSLog

public final class EncryptionService: @unchecked Sendable {
    nonisolated(unsafe) public static let shared = EncryptionService()
    
    private let salt: Data
    private var masterKey: SymmetricKey?
    
    private init() {
        self.salt = Data(hexString: AppConfig.encryptionSalt) ?? Data()
    }

    public var isReady: Bool { masterKey != nil }
    
    public func setup(with passphrase: String) {
        guard let passwordData = passphrase.data(using: .utf8) else { return }
        
        var derivedBytes = [UInt8](repeating: 0, count: 32)
        let result = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase, passwordData.count,
            [UInt8](salt), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            600_000,
            &derivedBytes, derivedBytes.count
        )
        
        guard result == kCCSuccess else {
            Logger.encryption.error("PBKDF2 failed: \(result)")
            return
        }
        
        self.masterKey = SymmetricKey(data: derivedBytes)
        Logger.encryption.info("Master Key derived and ready.")
    }

    /// Derives stable pseudo-random data of specified length for a given context (domain separation)
    public func derive(info: String, count: Int) -> Data? {
        guard let master = masterKey else { return nil }
        let derivedKey = HKDF<SHA256>.deriveKey(
            inputKeyMaterial: master,
            info: info.data(using: .utf8)!,
            outputByteCount: count
        )
        return derivedKey.withUnsafeBytes { Data($0) }
    }
}

// MARK: - Helpers

extension Data {
    init?(hexString: String) {
        let len = hexString.count / 2
        var data = Data(capacity: len)
        var i = hexString.startIndex
        for _ in 0..<len {
            let j = hexString.index(i, offsetBy: 2)
            if let byte = UInt8(hexString[i..<j], radix: 16) {
                data.append(byte)
            } else {
                return nil
            }
            i = j
        }
        self = data
    }
}

extension Logger {
    static let encryption = Logger(subsystem: Bundle.main.bundleIdentifier!, category: "EncryptionService")
}
