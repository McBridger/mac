import Foundation
import Combine
import CoreModels
import BluetoothService
import ClipboardService

@MainActor
class AppViewModel: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var bluetoothPowerState: BluetoothPowerState = .poweredOff
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var clipboardHistory: [String] = []

    // MARK: - Services
    private let bluetoothService: BluetoothManager
    private let clipboardService: ClipboardManager

    private var cancellables = Set<AnyCancellable>()

    init(bluetoothService: BluetoothManager, clipboardService: ClipboardManager) {
        self.bluetoothService = bluetoothService
        self.clipboardService = clipboardService
        setupBindings()
    }

    private func setupBindings() {
        // MARK: - Bluetooth State Bindings
        bluetoothService.$power
            .receive(on: DispatchQueue.main)
            .assign(to: \.bluetoothPowerState, on: self)
            .store(in: &cancellables)

        bluetoothService.$connection
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectionState, on: self)
            .store(in: &cancellables)
            
        bluetoothService.$devices
            .receive(on: DispatchQueue.main)
            .assign(to: \.connectedDevices, on: self)
            .store(in: &cancellables)
        
        // MARK: - Flow Bindings
        
        // Flow 1: Local clipboard changes -> Send over Bluetooth
        clipboardService.$update
            .sink { [weak self] message in
                self?.bluetoothService.send(message: message)
                self?.clipboardHistory.append(message.value)
            }
            .store(in: &cancellables)

        // Flow 2: Remote messages -> Apply to local clipboard
        bluetoothService.$message
            .receive(on: DispatchQueue.main)
            .sink { [weak self] message in
                if message.type == .CLIPBOARD {
                    self?.clipboardService.setText(message.value)
                }
            }
            .store(in: &cancellables)
    }
}

