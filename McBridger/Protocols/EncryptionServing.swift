import Foundation
import Combine

public protocol EncryptionServing: AnyObject {
    var isReady: CurrentValueSubject<Bool, Never> { get }
    var mnemonic: CurrentValueSubject<String, Never> { get }
    
    func setup(with passphrase: String)
    func reset()
    func derive(info: String, count: Int) -> Data?
    func encrypt(_ data: Data, key: Data) -> Data?
    func decrypt(_ data: Data, key: Data) -> Data?
    
    // From extension/logic
    func encryptMessage(_ message: BridgerMessage) -> Data?
    func decryptMessage(_ data: Data, address: String?) throws -> BridgerMessage
}
