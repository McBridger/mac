#if DEBUG
import Combine
import CoreBluetooth
import Foundation

class MockBluetoothManager: BluetoothManaging, @unchecked Sendable {
    let power = CurrentValueSubject<BluetoothPowerState, Never>(.poweredOn)
    let connection = CurrentValueSubject<ConnectionState, Never>(.disconnected)
    let devices = CurrentValueSubject<[DeviceInfo], Never>([])
    let data = PassthroughSubject<(data: Data, from: String), Never>()

    public init() {
        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(TestNotification.connectDevice),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.simulateDeviceConnection()
        }

        DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name(TestNotification.receiveData),
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let payloadHex = notification.object as? String else { return }

            let payload = Data(hexString: payloadHex) ?? Data()

            // Small delay to ensure the event is processed after the test expectation is set up
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.data.send((data: payload, from: "mock-device"))
            }
        }
    }

    func start(advertise: Data, service: Data, characteristic: Data) async {
        connection.send(.advertising)
    }

    func simulateDeviceConnection() {
        self.connection.send(.connected)

        // Small delay to simulate device identification after link establishment
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            Task {
                let mockID = UUID()
                await self.markDeviceAsIntroduced(id: mockID, name: "Pixel 7 Pro (Mock)")
            }
        }
    }

    func stop() async {
        connection.send(.disconnected)
    }

    func send(data: Data) async {
        print("Mock BT Send: \(data.count) bytes")
        // Notify the test suite that data was sent
        // Using a string for the data to avoid potential issues with Data over DistributedNotification
        DistributedNotificationCenter.default().postNotificationName(
            NSNotification.Name(TestNotification.dataSent),
            object: data.hexString,
            userInfo: nil,
            deliverImmediately: true
        )
    }

    func markDeviceAsIntroduced(id: UUID, name: String) async {
        let device = DeviceInfo(id: id, name: name, isIntroduced: true)
        devices.send([device])
    }
}
#endif