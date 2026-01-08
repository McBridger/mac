import CoreBluetooth
import Foundation

/// A proxy to bridge the gap between synchronous CoreBluetooth delegates 
/// and our asynchronous BluetoothManager actor.
public final class BluetoothDelegate: NSObject, CBPeripheralManagerDelegate, @unchecked Sendable {
    private weak var actor: BluetoothManager?

    public init(actor: BluetoothManager) {
        self.actor = actor
    }

    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let state = peripheral.state
        Task { [weak actor] in
            await actor?.handleHardwareStateChange(state)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { [weak actor] in
            await actor?.handleServiceAdded(service, error: error)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        Task { [weak actor] in
            await actor?.handleCentralSubscribed(central, characteristic: characteristic)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        Task { [weak actor] in
            await actor?.handleCentralUnsubscribed(central, characteristic: characteristic)
        }
    }

    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        Task { [weak actor] in
            await actor?.handleReceiveWrite(requests)
        }
    }
}
