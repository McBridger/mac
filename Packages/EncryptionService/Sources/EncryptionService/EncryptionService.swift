import Foundation
import CryptoKit
import CommonCrypto
import OSLog

public final class EncryptionService: @unchecked Sendable {
    public static let shared = EncryptionService()
    
    private var salt: Data?
    private var masterKey: SymmetricKey?
    
    private let logger = Logger(subsystem: "com.mcbridger.SecurityService", category: "Encryption")
    
    private init() {
        // We don't have the salt yet, it will be provided via setup or bootstrap
    }

    public var isReady: Bool { masterKey != nil }
    
    /// Returns the stored mnemonic if it exists
    public var storedMnemonic: String? {
        KeychainHelper.load()
    }

    /// Initializes the service with a salt and attempts to load the mnemonic from Keychain
    public func bootstrap(saltHex: String) {
        self.salt = Data(hexString: saltHex)
        if let mnemonic = KeychainHelper.load() {
            logger.info("Mnemonic found in Keychain, auto-initializing.")
            setup(with: mnemonic)
        }
    }
    
    public func setup(with passphrase: String) {
        guard let salt = self.salt else {
            logger.error("Setup failed: Salt not provided. Call bootstrap() first.")
            return
        }
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
            logger.error("PBKDF2 failed: \(result)")
            return
        }
        
        // Persist to Keychain
        KeychainHelper.save(passphrase)
        
        self.masterKey = SymmetricKey(data: derivedBytes)
        logger.info("Master Key derived and persisted.")
    }

    public func reset() {
        KeychainHelper.delete()
        masterKey = nil
        logger.info("Security state reset.")
    }

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
