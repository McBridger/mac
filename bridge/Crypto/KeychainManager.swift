import Foundation
import Security
import OSLog

internal final class KeychainManager: KeychainManaging {
    private let logger = Logger(subsystem: "com.mcbridger.Keychain", category: "Manager")
    private let service = "com.mcbridger.sync-phrase"

    private func query(for key: KeychainKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key.rawValue
        ]
    }

    func save(_ value: Data, for key: KeychainKey) {
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

    func load(key: KeychainKey) -> Data? {
        var q = query(for: key)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne

        var dataTypeRef: AnyObject?
        let status = SecItemCopyMatching(q as CFDictionary, &dataTypeRef)

        return (status == errSecSuccess) ? (dataTypeRef as? Data) : nil
    }

    func delete(key: KeychainKey) {
        SecItemDelete(query(for: key) as CFDictionary)
    }
    
    func deleteAll() {
        delete(key: .mnemonic)
        delete(key: .masterKey)
    }
}