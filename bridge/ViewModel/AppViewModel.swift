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
        if let data = KeychainHelper.load(key: .mnemonic) {
            return String(data: data, encoding: .utf8)
        }
        return nil
    }
    
    private func setupBindings() {
        // We listen to the Broker (AppLogic) and bring everything to the Main Thread
        appLogic.state
            .receive(on: RunLoop.main)
            .sink { [weak self] in self?.state = $0 }
            .store(in: &cancellables)
            
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