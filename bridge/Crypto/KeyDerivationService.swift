import Foundation
import CryptoKit
import CommonCrypto
import OSLog

public final class KeyDerivationService {
    private let logger = Logger(subsystem: "com.mcbridger.Security", category: "Derivation")
    
    public init() {}

    public func deriveAndSave(mnemonic: String, saltHex: String) -> Bool {
        guard let salt = Data(hexString: saltHex) else { return false }
        guard let passwordData = mnemonic.data(using: .utf8) else { return false }
        
        var derivedBytes = [UInt8](repeating: 0, count: 32)
        let result = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            mnemonic, passwordData.count,
            [UInt8](salt), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            600_000,
            &derivedBytes, derivedBytes.count
        )
        
        guard result == kCCSuccess else {
            logger.error("PBKDF2 failed: \(result)")
            return false
        }
        
        let masterKeyData = Data(derivedBytes)
        
        KeychainHelper.save(passwordData, for: .mnemonic)
        KeychainHelper.save(masterKeyData, for: .masterKey)
        
        logger.info("Master Key derived and persisted with mnemonic.")
        return true
    }
}

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
