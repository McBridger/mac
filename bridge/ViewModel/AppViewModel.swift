import Factory
import Foundation
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var state: BrokerState = .idle
    @Published var bluetoothPowerState: BluetoothPowerState = .poweredOff
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var clipboardHistory: [String] = []
    @Published var mnemonic: String? = nil
    
    @Injected(\.appLogic) private var logic
    @Injected(\.encryptionService) private var encryption
    @Injected(\.bluetoothManager) private var bluetooth
    
    public init() {
        setupBindings()
    }
    
    func setup(mnemonic: String) {
        logic.setup(mnemonic: mnemonic)
    }
    
    func resetSecurity() {
        logic.reset()
    }
    
    private func setupBindings() {
        // 1. Unified Status (The Brain)
        Publishers.CombineLatest3(logic.state, bluetooth.power, bluetooth.connection)
            .receive(on: RunLoop.main)
            .map { logicState, power, connection -> BrokerState in
                if logicState == .idle || logicState == .encrypting {
                    return logicState
                }
                
                if power == .poweredOff {
                    return .bluetoothOff
                }
                
                switch connection {
                    case .advertising: return .advertising
                    case .connected: return .connected
                    case .disconnected: return .ready
                }
            }
            .assign(to: &$state)

        // 2. Direct mirrors from BluetoothManager
        bluetooth.power.receive(on: RunLoop.main).assign(to: &$bluetoothPowerState)
        bluetooth.connection.receive(on: RunLoop.main).assign(to: &$connectionState)
        bluetooth.devices.receive(on: RunLoop.main).assign(to: &$connectedDevices)
        
        // 3. Logic mirrors
        logic.clipboardHistory.receive(on: RunLoop.main).assign(to: &$clipboardHistory)

        // 4. Mnemonic state
        encryption.mnemonic
            .map { $0.isEmpty ? nil : $0 }
            .receive(on: RunLoop.main)
            .assign(to: &$mnemonic)
    }
}