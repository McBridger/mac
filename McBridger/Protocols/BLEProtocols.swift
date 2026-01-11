import Foundation

public struct BLEConfig: Equatable, Sendable {
    public let advertise: Data
    public let service: Data
    public let characteristic: Data
    
    public init(advertise: Data, service: Data, characteristic: Data) {
        self.advertise = advertise
        self.service = service
        self.characteristic = characteristic
    }
}

public enum BLEStatus: Sendable {
    case unknown
    case resetting
    case unsupported
    case unauthorized
    case poweredOff
    case poweredOn
}

public enum BLEDriverEvent: Sendable {
    case didUpdateState(BLEStatus)
    case didSubscribe(central: UUID)
    case didUnsubscribe(central: UUID)
    case didReceiveData(Data, from: UUID)
    case didAddService(Error?)
    case isReadyToResend
    case isAdvertising(Bool)
}

public protocol BLEDriverProtocol: Sendable {
    var eventStream: AsyncStream<BLEDriverEvent> { get }
    func advertise(_ config: BLEConfig)
    func stop()
    func send(_ data: Data, to targetUUIDs: [UUID]) -> Bool
}