import CoreBluetooth
import Foundation
import OSLog

public final class BLEDriver: NSObject, BLEDriverProtocol, @unchecked Sendable {
    
    private let logger = Logger(subsystem: "com.mcbridger.Transport", category: "BLEDriver")
    private let queue = DispatchQueue(label: "com.mcbridger.ble-driver", qos: .userInitiated)
    
    private var peripheral: CBPeripheralManager!
    private var transferCharacteristic: CBMutableCharacteristic?
    private var centralsMap: [UUID: CBCentral] = [:]

    private var config: BLEConfig?
    
    private let continuation: AsyncStream<BLEDriverEvent>.Continuation
    public let eventStream: AsyncStream<BLEDriverEvent>
    
    public override init() {
        var c: AsyncStream<BLEDriverEvent>.Continuation!
        self.eventStream = AsyncStream { c = $0 }
        self.continuation = c
        
        super.init()
        self.peripheral = CBPeripheralManager(delegate: self, queue: queue)
    }

    public func advertise(_ config: BLEConfig) {
        queue.async {
            self.logger.info("📝 Driver received config intent.")
            self.config = config
            
            if self.peripheral.state != .poweredOn { return }
            self.applyConfig(config)
        }
    }

    public func stop() {
        queue.async {
            self.logger.info("🛑 Stop requested. Clearing config.")
            self.config = nil
            self.peripheral.stopAdvertising()
            self.peripheral.removeAllServices()
            self.continuation.yield(.isAdvertising(false))
        }
    }
    
    public func send(_ data: Data, to targetUUIDs: [UUID]) -> Bool {
        return queue.sync {
            guard let char = transferCharacteristic else { return false }
            
            let targets = targetUUIDs.compactMap { centralsMap[$0] }
            if targets.isEmpty && !targetUUIDs.isEmpty { return true }
            
            return self.peripheral.updateValue(data, for: char, onSubscribedCentrals: targets.isEmpty ? nil : targets)
        }
    }

    private func applyConfig(_ config: BLEConfig) {
        self.peripheral.stopAdvertising()
        self.peripheral.removeAllServices()

        let char = CBMutableCharacteristic(
            type: CBUUID(data: config.characteristic),
            properties: [.read, .write, .notify],
            value: nil,
            permissions: [.readable, .writeable]
        )

        let service = CBMutableService(type: CBUUID(data: config.service), primary: true)
        service.characteristics = [char]

        self.transferCharacteristic = char
        self.logger.info("⚙️ Pushing service structure to CoreBluetooth...")
        self.peripheral.add(service)
    }
    
    private func mapStatus(_ state: CBManagerState) -> BLEStatus {
        switch state {
        case .poweredOn: return .poweredOn
        case .poweredOff: return .poweredOff
        case .unauthorized: return .unauthorized
        case .unsupported: return .unsupported
        case .resetting: return .resetting
        default: return .unknown
        }
    }
}

extension BLEDriver: CBPeripheralManagerDelegate {
    public func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let status = mapStatus(peripheral.state)
        continuation.yield(.didUpdateState(status))
        
        if peripheral.state == .poweredOn {
            if let config = self.config {
                logger.info("🔌 Power restored. Auto-applying saved config...")
                self.applyConfig(config)
            }
        }
    }

    public func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        if let error = error {
            logger.error("❌ Failed to start advertising: \(error.localizedDescription)")
            continuation.yield(.isAdvertising(false))
            return
        }
        logger.info("📢 CoreBluetooth confirms: Advertising is ACTIVE.")
        continuation.yield(.isAdvertising(true))
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        continuation.yield(.didAddService(error))
        
        if let error {
            logger.error("❌ Failed to add service: \(error.localizedDescription)")
            return
        }
        
        if let config = self.config {
            logger.info("📢 Service added. Starting Advertising...")
            peripheral.startAdvertising([CBAdvertisementDataServiceUUIDsKey: [CBUUID(data: config.advertise)]])
        }
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        centralsMap[central.identifier] = central
        continuation.yield(.didSubscribe(central: central.identifier))
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        centralsMap.removeValue(forKey: central.identifier)
        continuation.yield(.didUnsubscribe(central: central.identifier))
    }
    
    public func peripheralManagerIsReady(toUpdateSubscribers peripheral: CBPeripheralManager) {
        continuation.yield(.isReadyToResend)
    }
    
    public func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        for request in requests {
            if let value = request.value {
                continuation.yield(.didReceiveData(value, from: request.central.identifier))
            }
            peripheral.respond(to: request, withResult: .success)
        }
    }
}