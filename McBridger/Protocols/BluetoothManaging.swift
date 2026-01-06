import Foundation
import Combine
import CoreBluetooth

public protocol BluetoothManaging: AnyObject {
    var power: CurrentValueSubject<BluetoothPowerState, Never> { get }
    var connection: CurrentValueSubject<ConnectionState, Never> { get }
    var devices: CurrentValueSubject<[DeviceInfo], Never> { get }
    var data: PassthroughSubject<(data: Data, from: String), Never> { get }
    
    func start(advertiseUUID: CBUUID, serviceUUID: CBUUID, characteristicUUID: CBUUID)
    func stop()
    func send(data: Data)
    func markDeviceAsIntroduced(id: UUID, name: String)
}
