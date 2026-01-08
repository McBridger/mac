import Foundation
import Combine
import CoreBluetooth

public protocol BluetoothManaging: AnyObject, Sendable {
    var power: CurrentValueSubject<BluetoothPowerState, Never> { get }
    var connection: CurrentValueSubject<ConnectionState, Never> { get }
    var devices: CurrentValueSubject<[DeviceInfo], Never> { get }
    var data: PassthroughSubject<(data: Data, from: String), Never> { get }

    func start(advertise: Data, service: Data, characteristic: Data) async
    func stop() async
    func send(data: Data) async
    func markDeviceAsIntroduced(id: UUID, name: String) async
}
