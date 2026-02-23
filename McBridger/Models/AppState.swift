import Foundation

// MARK: - Enums for BLE State

public enum BluetoothPowerState: String, Sendable {
    case poweredOn = "Bluetooth On"
    case poweredOff = "Bluetooth Off"
}

public enum BleState: String, Sendable {
    case idle = "Idle"
    case advertising = "Advertising"
    case connected = "Connected"
    case disconnected = "Disconnected"
}

public struct TransportStatus<T: Sendable & Equatable>: Sendable, Equatable {
    public let current: T
    public let error: String?
    
    public init(current: T, error: String? = nil) {
        self.current = current
        self.error = error
    }
}

public struct BrokerState: Sendable, Equatable {
    public var ble: TransportStatus<BleState>
    public var tcp: TransportStatus<TcpState>
    public var encryption: TransportStatus<EncryptionState>
    public var activePorters: [String: Porter]
    
    public static let idle = BrokerState(
        ble: .init(current: .idle),
        tcp: .init(current: .idle),
        encryption: .init(current: .idle),
        activePorters: [:]
    )
}

public enum BluetoothEvent: Sendable {
    case powerStateChanged(BluetoothPowerState)
    case bleStateChanged(BleState)
    case deviceConnected(DeviceInfo)
    case deviceDisconnected(DeviceInfo)
    case messageReceived(BridgerMessage, from: String)
}