import OSLog
import CryptoKit
import Combine
import Foundation
import CommonCrypto

public final class EncryptionService {
    private let queue = DispatchQueue(label: "com.mcbridger.encryption-lock", attributes: .concurrent)
    private let logger = Logger(subsystem: "com.mcbridger.SecurityService", category: "Encryption")
    private let _salt: Data = Data(hexString: AppConfig.encryptionSalt)!
   
    private var _masterKey: SymmetricKey?
    
    public let isReady = CurrentValueSubject<Bool, Never>(false)
    public let mnemonic = CurrentValueSubject<String, Never>("")
    
    public init() {
        let keyData = KeychainHelper.load(key: .masterKey)
        let mnemonicData = KeychainHelper.load(key: .mnemonic)

        if let keyData = keyData { self._masterKey = SymmetricKey(data: keyData)}
        if let data = mnemonicData { self.mnemonic.send(String(data: data, encoding: .utf8) ?? "") }

        if (self.mnemonic.value != "") && (self._masterKey != nil) {
            logger.info("Found cached Master Key. Instant start.")
            self.isReady.send(true)
        } else {
            logger.info("No cached Master Key found. Manual setup required.")
        }
    }
    
    /// Heavy lifting: derives key from mnemonic and persists both for future instant starts.
    public func setup(with passphrase: String) {
        let salt = self._salt

        DispatchQueue.global(qos: .userInitiated).async {
            guard let derivedKey = self.calculateKey(passphrase: passphrase, salt: salt) else {
                self.logger.error("PBKDF2 failed during setup.")
                return
            }

            self.queue.async(flags: .barrier) {
                self._masterKey = derivedKey
                self.mnemonic.send(passphrase)
                KeychainHelper.save(passphrase.data(using: .utf8)!, for: .mnemonic)
                KeychainHelper.save(derivedKey.withUnsafeBytes { Data($0) }, for: .masterKey)
                self.isReady.send(true)
                self.logger.info("Master Key derived and cached in Keychain.")
            }
        }
    }

    private func calculateKey(passphrase: String, salt: Data) -> SymmetricKey? {
        guard let passwordData = passphrase.data(using: .utf8) else { return nil }
        
        var derivedBytes = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase, passwordData.count,
            [UInt8](salt), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            600_000,
            &derivedBytes, derivedBytes.count
        )

        return (status == kCCSuccess) ? SymmetricKey(data: Data(derivedBytes)) : nil
    }

    public func reset() {
        queue.async(flags: .barrier) {
            KeychainHelper.deleteAll()
            self._masterKey = nil
            self.mnemonic.send("")
            self.isReady.send(false)
            self.logger.info("Security state reset confirmed.")
        }
    }

    public func derive(info: String, count: Int) -> Data? {
        queue.sync {
            guard let master = _masterKey else { return nil }
            let derivedKey = HKDF<SHA256>.deriveKey(
                inputKeyMaterial: master,
                info: info.data(using: .utf8)!,
                outputByteCount: count
            )
            return derivedKey.withUnsafeBytes { Data($0) }
        }
    }

    // MARK: - AES-GCM Cryptography

    public func encrypt(_ data: Data, key: Data) -> Data? {
        do {
            let symmetricKey = SymmetricKey(data: key)
            let sealedBox = try AES.GCM.seal(data, using: symmetricKey)
            return sealedBox.combined
        } catch {
            logger.error("Encryption failed: \(error.localizedDescription)")
            return nil
        }
    }

    public func decrypt(_ data: Data, key: Data) -> Data? {
        do {
            let symmetricKey = SymmetricKey(data: key)
            let sealedBox = try AES.GCM.SealedBox(combined: data)
            return try AES.GCM.open(sealedBox, using: symmetricKey)
        } catch {
            logger.error("Decryption failed: \(error.localizedDescription)")
            return nil
        }
    }
}