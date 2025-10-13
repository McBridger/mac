import Foundation
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

    private var activeTasks = Set<Task<Void, Never>>()

    init(bluetoothService: BluetoothManager, clipboardService: ClipboardManager) {
        self.bluetoothService = bluetoothService
        self.clipboardService = clipboardService
        setupBindings()
    }

    private func setupBindings() {
        // MARK: - Bluetooth State Bindings
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await state in self.bluetoothService.powerState {
                self.bluetoothPowerState = state
            }
        }
        .store(in: &activeTasks)

        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await state in self.bluetoothService.connectionState {
                self.connectionState = state
            }
        }
        .store(in: &activeTasks)
            
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await devices in self.bluetoothService.deviceList {
                self.connectedDevices = devices
            }
        }
        .store(in: &activeTasks)
        
        // MARK: - Clipboard Flow Bindings
        
        // Flow 1: Local clipboard changes -> Send over Bluetooth
        Task { [weak self] in
            guard let self = self else { return }
            for await message in self.clipboardService.messageStream {
                await self.bluetoothService.send(message: message)
                await MainActor.run {
                    self.clipboardHistory.append(message.value)
                }
            }
        }
        .store(in: &activeTasks)

        // Flow 2: Remote messages -> Apply to local clipboard
        Task { @MainActor [weak self] in
            guard let self = self else { return }
            for await message in await self.bluetoothService.messages {
                if message.type == .CLIPBOARD {
                    self.clipboardService.setText(message.value)
                }
            }
        }
        .store(in: &activeTasks)
    }
}

extension Task where Success == Void, Failure == Never {
    func store(in set: inout Set<Task<Void, Never>>) {
        set.insert(self)
    }
}
