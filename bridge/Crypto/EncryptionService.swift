import OSLog
import CryptoKit
import Combine
import Foundation
import CommonCrypto

public final class EncryptionService {
    
    private let queue = DispatchQueue(label: "com.mcbridger.encryption-lock", attributes: .concurrent)
    private var _masterKey: SymmetricKey?
    private var _salt: Data?
    
    @UseState public private(set) var isReady: Bool = false
    @UseState public private(set) var hasStoredMnemonic: Bool = false
    
    private let logger = Logger(subsystem: "com.mcbridger.SecurityService", category: "Encryption")
    
    public init() {
        self.hasStoredMnemonic = KeychainHelper.load(key: .mnemonic) != nil
    }

    public var storedMnemonic: String? {
        guard let data = KeychainHelper.load(key: .mnemonic) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Quick bootstrap: only loads pre-calculated key if it exists.
    public func bootstrap(saltHex: String) {
        let salt = Data(hexString: saltHex)
        queue.async(flags: .barrier) { self._salt = salt }
        
        if let keyData = KeychainHelper.load(key: .masterKey) {
            logger.info("Found cached Master Key. Instant start.")
            queue.async(flags: .barrier) {
                self._masterKey = SymmetricKey(data: keyData)
                self.isReady = true
            }
        } else {
            logger.info("No cached Master Key found. Manual setup required.")
        }
    }
    
    /// Heavy lifting: derives key from mnemonic and persists both for future instant starts.
    public func setup(with passphrase: String) -> AnyPublisher<Bool, Never> {
        let result = PassthroughSubject<Bool, Never>()
        let salt = queue.sync { _salt }
        
        DispatchQueue.global(qos: .userInitiated).async {
            if let s = salt {
                self.internalSetup(with: passphrase, salt: s)
            } else {
                self.logger.error("Setup failed: No salt available.")
            }
            result.send(self.isReady)
            result.send(completion: .finished)
        }
        
        return result.eraseToAnyPublisher()
    }

    private func internalSetup(with passphrase: String, salt: Data) {
        guard let passwordData = passphrase.data(using: .utf8) else { return }
        
        var derivedBytes = [UInt8](repeating: 0, count: 32)
        let status = CCKeyDerivationPBKDF(
            CCPBKDFAlgorithm(kCCPBKDF2),
            passphrase, passwordData.count,
            [UInt8](salt), salt.count,
            CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),
            600_000,
            &derivedBytes, derivedBytes.count
        )
        
        guard status == kCCSuccess else {
            logger.error("PBKDF2 failed during setup.")
            return
        }
        
        let derivedData = Data(derivedBytes)
        let key = SymmetricKey(data: derivedData)
        
        queue.async(flags: .barrier) {
            self._masterKey = key
            
            // Persist for instant access on next launch
            if let data = passphrase.data(using: .utf8) {
                KeychainHelper.save(data, for: .mnemonic)
            }
            KeychainHelper.save(derivedData, for: .masterKey)
            
            self.hasStoredMnemonic = true
            self.isReady = true
            self.logger.info("Master Key derived and cached in Keychain.")
        }
    }

    public func reset() -> AnyPublisher<Void, Never> {
        let done = PassthroughSubject<Void, Never>()
        queue.async(flags: .barrier) {
            KeychainHelper.deleteAll()
            self._masterKey = nil
            self.isReady = false
            self.hasStoredMnemonic = false
            self.logger.info("Security state reset confirmed.")
            done.send()
            done.send(completion: .finished)
        }
        return done.eraseToAnyPublisher()
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
}