import Factory
import Foundation
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties (Locked to MainActor)
    @Published var state: BrokerState = .idle
    @Published var bluetoothPowerState: BluetoothPowerState = .poweredOff
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var clipboardHistory: [String] = []
    
    @Injected(\.appLogic) private var appLogic
    
    private var cancellables = Set<AnyCancellable>()

    init() {
        setupBindings()
    }
    
    func setup(mnemonic: String) {
        appLogic.setup(mnemonic: mnemonic)
    }
    
    func resetSecurity() {
        appLogic.reset()
    }

    var storedMnemonic: String? {
        appLogic.storedMnemonic
    }
    
    private func setupBindings() {
        // 1. Unified Status (The Brain)
        Publishers.CombineLatest3(appLogic.state, appLogic.bluetoothPower, appLogic.connectionState)
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

        // 2. Individual mirrors for backward compatibility or specific UI elements
        appLogic.bluetoothPower
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.bluetoothPowerState = $0 }
            .store(in: &cancellables)
            
        appLogic.connectionState
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectionState = $0 }
            .store(in: &cancellables)
            
        appLogic.devices
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.connectedDevices = $0 }
            .store(in: &cancellables)
            
        appLogic.clipboardHistory
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.clipboardHistory = $0 }
            .store(in: &cancellables)
    }
}