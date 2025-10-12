import Foundation

// MARK: - Enums for BLE State

public enum BluetoothPowerState: String, Sendable {
    case poweredOn = "Bluetooth On"
    case poweredOff = "Bluetooth Off"
}

public enum ConnectionState: String, Sendable {
    case disconnected = "Disconnected"
    case advertising = "Advertising"
    case connected = "Connected to Android"
}

public enum BluetoothEvent: Sendable {
    case powerStateChanged(BluetoothPowerState)
    case connectionStateChanged(ConnectionState)
    case deviceConnected(DeviceInfo)
    case deviceDisconnected(DeviceInfo)
    case messageReceived(BridgerMessage, from: String) // centralID as String
}