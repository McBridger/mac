import Factory
import Foundation
import Combine
import AppKit

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published var state: BrokerState = .idle
    @Published var historyPorters: [Porter] = []
    
    var activePorters: [Porter] {
        Array(state.activePorters.values).sorted(by: { $0.timestamp > $1.timestamp })
    }
    
    var bleState: BleState { state.ble.current }
    var tcpState: TcpState { state.tcp.current }
    
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var clipboardHistory: [String] = []
    @Published var mnemonic: String? = nil
    
    @Injected(\.broker) private var logic
    @Injected(\.encryptionService) private var encryption
    @Injected(\.bluetoothManager) private var bluetooth
    @Injected(\.historyManager) private var history
    
    private var cancellables = Set<AnyCancellable>()

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
        // 1. Core State Mapping
        logic.state
            .receive(on: RunLoop.main)
            .assign(to: &$state)

        // 2. History Mapping
        history.items
            .receive(on: RunLoop.main)
            .sink { [weak self] items in
                self?.historyPorters = items.sorted(by: { $0.timestamp > $1.timestamp })
                self?.clipboardHistory = items.compactMap { $0.data }.filter { $0.count < 1000 }
            }
            .store(in: &cancellables)

        // 3. Direct mirrors from BluetoothManager
        bluetooth.devices.receive(on: RunLoop.main).assign(to: &$connectedDevices)
        
        // 4. Mnemonic state
        encryption.mnemonic
            .map { $0.isEmpty ? nil : $0 }
            .receive(on: RunLoop.main)
            .assign(to: &$mnemonic)
    }
}