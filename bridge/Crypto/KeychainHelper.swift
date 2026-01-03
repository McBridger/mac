import Foundation
import Security
import OSLog

internal enum KeychainHelper {
    private static let logger = Logger(subsystem: "com.mcbridger.Keychain", category: "Helper")
    private static let service = "com.mcbridger.sync-phrase"

    enum Key: String {
        case mnemonic = "primary-mnemonic"
        case masterKey = "master-key"
    }

    private static func query(for key: Key) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    static func save(_ value: Data, for key: Key) {
        let base = query(for: key)
        let status = SecItemCopyMatching(base as CFDictionary, nil)
        
        switch status {
        case errSecSuccess:
            let attributesToUpdate: [String: Any] = [kSecValueData as String: value]
            SecItemUpdate(base as CFDictionary, attributesToUpdate as CFDictionary)
        case errSecItemNotFound:
            var q = base
            q[kSecValueData as String] = value
            q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
            SecItemAdd(q as CFDictionary, nil)
        default:
            logger.error("Keychain error for \(key.rawValue): \(status)")
        }
    }

    static func load(key: Key) -> Data? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &dataTypeRef)

        return (status == errSecSuccess) ? (dataTypeRef as? Data) : nil
    }

    static func delete(key: Key) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
    
    static func deleteAll() {
        delete(key: .mnemonic)
        delete(key: .masterKey)
    }
}
