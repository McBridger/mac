import CoreBluetooth
import Foundation

public protocol AppConfiguring: Sendable {
    var encryptionSalt: String { get }
    var mnemonic: String? { get }
    var mnemonicLength: Int { get }
}

public final class AppConfig: AppConfiguring {
    public let encryptionSalt: String
    public let mnemonic: String?
    public let mnemonicLength: Int

    public init() {
        self.encryptionSalt = (try? Config.value(for: "ENCRYPTION_SALT")) ?? ""
        assert(!encryptionSalt.isEmpty, "ENCRYPTION_SALT must be provided in Info.plist/xcconfig")
        self.mnemonic = try? Config.value(for: "MNEMONIC_LOCAL")
        self.mnemonicLength = (try? Config.value(for: "MNEMONIC_LENGTH")) ?? 6
    }
}

private enum Config {
    enum Error: Swift.Error {
        case missingKey, invalidValue
    }

    static func value<T>(for key: String) throws -> T where T: LosslessStringConvertible {
        guard let object = Bundle.main.object(forInfoDictionaryKey: key) else {
            throw Error.missingKey
        }

        switch object {
        case let value as T:
            return value
        case let string as String:
            guard let value = T(string) else { fallthrough }
            return value
        default:
            throw Error.invalidValue
        }
    }
}
