import CryptoKit
import Foundation
import OSLog

private let ENCRYPTION_DOMAIN = "McBridge_Encryption_Domain"

extension EncryptionService {
    private static let logger = Logger(subsystem: "com.mcbridger.Crypto", category: "Message")

    /**
     * Encrypts BridgerMessage for secure transfer
     */
    public func encryptMessage(_ message: BridgerMessage) -> Data? {
        guard let key = self.derive(info: ENCRYPTION_DOMAIN, count: 32) else { return nil }
        guard let data = message.toData() else { return nil }
        return self.encrypt(data, key: key)
    }

    /**
     * Decrypts and creates a BridgerMessage from encrypted data
     */
    public func decryptMessage(_ data: Data, address: String? = nil) throws -> BridgerMessage {
        guard let key = self.derive(info: ENCRYPTION_DOMAIN, count: 32) else {
            throw BridgerMessageError.decryptionFailed
        }

        guard let decryptedData = self.decrypt(data, key: key) else {
            throw BridgerMessageError.decryptionFailed
        }

        return try BridgerMessage.fromData(decryptedData, address: address)
    }
}
