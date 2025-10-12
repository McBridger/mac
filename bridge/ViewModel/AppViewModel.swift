import Foundation
import Combine
import CoreBluetooth // Для CBCentral
import CoreModels
import BluetoothService
import ClipboardService
import NotificationService


class AppViewModel: ObservableObject {
    // MARK: - Published Properties for UI
    @Published var bluetoothPowerState: BluetoothPowerState = .poweredOff
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevices: [DeviceInfo] = []
    @Published var receivedClipboardText: String = "Ожидание данных от Android..."

    // MARK: - Services
    private let bluetoothService: BluetoothService
    private let clipboardService: ClipboardService
    private let notificationService: NotificationService

    private var cancellables = Set<AnyCancellable>()

    init(bluetoothService: BluetoothService, clipboardService: ClipboardService, notificationService: NotificationService) {
        self.bluetoothService = bluetoothService
        self.clipboardService = clipboardService
        self.notificationService = notificationService

        setupBindings()
        self.bluetoothService.delegate = self
        self.clipboardService.delegate = self
    }

    private func setupBindings() {
        bluetoothService.$powerState
            .assign(to: \.bluetoothPowerState, on: self)
            .store(in: &cancellables)

        bluetoothService.$connectionState
            .assign(to: \.connectionState, on: self)
            .store(in: &cancellables)

        bluetoothService.$connectedDevices
            .assign(to: \.connectedDevices, on: self)
            .store(in: &cancellables)
    }

    // MARK: - Public Methods
    func sendClipboardText(_ text: String) {
        let message = BridgerMessage(type: .CLIPBOARD, value: text)
        bluetoothService.send(message: message)
    }
}

// MARK: - BluetoothServiceDelegate
extension AppViewModel: BluetoothServiceDelegate {
    func bluetoothService(_ service: BluetoothService, didUpdatePowerState state: BluetoothPowerState) {
        // UI будет обновлен через @Published свойство
    }

    func bluetoothService(_ service: BluetoothService, didUpdateConnectionState state: ConnectionState) {
        // UI будет обновлен через @Published свойство
    }

    func bluetoothService(_ service: BluetoothService, didConnectDevice device: DeviceInfo) {
        notificationService.showNotification(title: "Device Connected", body: "New device connected: \(device.name)")
    }

    func bluetoothService(_ service: BluetoothService, didDisconnectDevice device: DeviceInfo) {
        notificationService.showNotification(title: "Device Disconnected", body: "Device disconnected: \(device.name)")
    }

    func bluetoothService(_ service: BluetoothService, didReceiveMessage message: BridgerMessage, from central: CBCentral) {
        switch message.type {
        case .CLIPBOARD:
            // Проверка на дублирование уже происходит в ClipboardService
            clipboardService.setClipboard(text: message.value)
            receivedClipboardText = message.value
            notificationService.showNotification(title: "Clipboard Synced", body: "Received from Android: \(message.value)")
        case .DEVICE_NAME:
            // Имя устройства уже обновляется в BluetoothService
            // Уведомление об изменении имени устройства отключено по запросу пользователя
            break
        }
    }
    
    func bluetoothService(_ service: BluetoothService, didUpdateDeviceName device: DeviceInfo) {
        // Имя устройства обновляется в BluetoothService, UI будет обновлен через @Published
        // Уведомление об изменении имени устройства отключено по запросу пользователя
    }
}

// MARK: - ClipboardServiceDelegate
extension AppViewModel: ClipboardServiceDelegate {
    func clipboardService(_ service: ClipboardService, didChangeText text: String) {
        print("Обнаружено изменение в буфере обмена Mac: \(text)")
        sendClipboardText(text)
    }
}