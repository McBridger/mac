import Foundation
import Combine
import CoreBluetooth

class MockBluetoothManager: BluetoothManaging {
    let power = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOn)
    let connection = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    let devices = CurrentValueSubject<[DeviceInfo], Never>([])
    let data = PassthroughSubject<(data: Data, from: String), Never>()
    
    public init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.mcbridger.test.connect_device"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.simulateDeviceConnection()
        }
    }

    func start(advertiseUUID: CBUUID, serviceUUID: CBUUID, characteristicUUID: CBUUID) {
        connection.send(.advertising)
    }
    
    func simulateDeviceConnection() {
        self.connection.send(.connected)
        
        // Small delay to simulate device identification after link establishment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            let mockID = UUID()
            self.markDeviceAsIntroduced(id: mockID, name: "Pixel 7 Pro (Mock)")
        }
    }
    
    func stop() {
        connection.send(.disconnected)
    }
    
    func send(data: Data) {
        print("Mock BT Send: \(data.count) bytes")
    }
    
    func markDeviceAsIntroduced(id: UUID, name: String) {
        let device = DeviceInfo(id: id, name: name, isIntroduced: true)
        devices.send([device])
    }
}
