import Foundation
import Combine

class MockEncryptionService: EncryptionServing {
    let isReady: CurrentValueSubject<Bool, Never>
    let mnemonic = CurrentValueSubject<String, Never>("")
    
    init() {
        let isCold = ProcessInfo.processInfo.arguments.contains("--cold-start")
        self.isReady = CurrentValueSubject<Bool, Never>(!isCold)
    }
    
    func setup(with passphrase: String) {
        mnemonic.send(passphrase)
        self.isReady.send(true)
    }
    
    func reset() {
        isReady.send(false)
        mnemonic.send("")
    }
    
    func derive(info: String, count: Int) -> Data? {
        return Data(repeating: 0, count: count)
    }
    
    func encrypt(_ data: Data, key: Data) -> Data? {
        return data // Just pass through for mock
    }
    
    func decrypt(_ data: Data, key: Data) -> Data? {
        return data
    }
    
    func encryptMessage(_ message: BridgerMessage) -> Data? {
        return message.toData()
    }
    
    func decryptMessage(_ data: Data, address: String?) throws -> BridgerMessage {
        return try BridgerMessage.fromData(data, address: address)
    }
}
