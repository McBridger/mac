#if DEBUG
import Foundation

internal final class MockKeychainManager: KeychainManaging {
    private var storage: [String: Data] = [:]

    func save(_ value: Data, for key: KeychainKey) {
        storage[key.rawValue] = value
    }

    func load(key: KeychainKey) -> Data? {
        return storage[key.rawValue]
    }

    func delete(key: KeychainKey) {
        storage.removeValue(forKey: key.rawValue)
    }

    func deleteAll() {
        storage.removeAll()
    }
}
#endif
