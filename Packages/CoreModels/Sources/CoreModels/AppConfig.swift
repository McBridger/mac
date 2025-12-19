import Foundation
import CoreBluetooth

public enum AppConfig {
    public static let advertiseID: String = try! Config.value(for: "ADVERTISE_UUID")
    public static let serviceID: String = try! Config.value(for: "SERVICE_UUID")
    public static let characteristicID: String = try! Config.value(for: "CHARACTERISTIC_UUID")
    public static let encryptionSalt: String = try! Config.value(for: "ENCRYPTION_SALT")
}

enum Config {
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
