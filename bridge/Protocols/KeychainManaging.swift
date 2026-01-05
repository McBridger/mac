import Foundation

public enum KeychainKey: String {
    case mnemonic = "primary-mnemonic"
    case masterKey = "master-key"
}

public protocol KeychainManaging: AnyObject {
    func save(_ value: Data, for key: KeychainKey)
    func load(key: KeychainKey) -> Data?
    func delete(key: KeychainKey)
    func deleteAll()
}
