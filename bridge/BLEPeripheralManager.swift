import Foundation
import CoreBluetooth
import Combine
import AppKit // Импорт для работы с буфером обмена NSPasteboard
import UserNotifications // Для современных уведомлений
import SystemConfiguration

// MARK: - Enums for BLE State

enum BluetoothPowerState: String {
    case poweredOn = "Bluetooth On"
    case poweredOff = "Bluetooth Off"
}

enum ConnectionState: String {
    case disconnected = "Disconnected"
    case advertising = "Advertising"
    case connected = "Connected to Android"
}

// MARK: - Message Protocol Structs

enum MESSAGE_TYPE: Int, Codable {
    case CLIPBOARD = 0
    case DEVICE_NAME = 1
}

struct Message: Codable {
    let t: MESSAGE_TYPE // type
    let p: String      // payload
}

// MARK: - Device Info Struct

class DeviceInfo: Identifiable, ObservableObject, Equatable {
    let id: UUID
    @Published var name: String // Теперь имя тоже @Published
    
    init(id: UUID, name: String) {
        self.id = id
        self.name = name
    }
    
    static func == (lhs: DeviceInfo, rhs: DeviceInfo) -> Bool {
        lhs.id == rhs.id
    }
}

// Класс управляет всей логикой Bluetooth и синхронизацией буфера обмена.
// NSObject - требование для делегатов CoreBluetooth.
// ObservableObject - чтобы SwiftUI мог следить за его изменениями.
// CBPeripheralManagerDelegate - чтобы получать события от Bluetooth-модуля.
class BLEPeripheralManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    // MARK: - Published Properties for SwiftUI
    // Эти свойства будут автоматически обновлять интерфейс
    @Published var receivedText: String = "Ожидание данных от Android..."
    @Published var powerState: BluetoothPowerState = .poweredOff
    @Published var connectionState: ConnectionState = .disconnected
    @Published var connectedDevices: [DeviceInfo] = [] // Список подключенных устройств с именами

    // MARK: - BLE Properties
    private var peripheralManager: CBPeripheralManager!
    private var textCharacteristic: CBMutableCharacteristic!
    // Эти UUID должны быть точно такими же, как и в Android-приложении
    let advertiseUUID = CBUUID(string: "fdd2")
    let bridgerServiceUUID = CBUUID(string: "ccfa23b4-ba6f-448a-827d-c25416ec432e")
    let characteristicUUID = CBUUID(string: "315eca9d-0dbc-498d-bb4d-1d59d7c5bc3b")
    
    // MARK: - Clipboard Sync Properties
    private var pasteboardTimer: Timer?
    private var lastChangeCount: Int = 0 // Счетчик изменений в буфере обмена
    private var isUpdatingInternally: Bool = false // Флаг для защиты от цикла
    private var lastSyncedText: String = "" // Хранит последний синхронизированный текст

    // MARK: - Lifecycle
    
    override init() {
        super.init()
        // Инициализация менеджера, которая запускает всю BLE-логику
        peripheralManager = CBPeripheralManager(delegate: self, queue: nil)
        
        // При запуске сразу читаем буфер обмена, чтобы иметь начальное значение
        if let currentPasteboard = NSPasteboard.general.string(forType: .string) {
            self.lastSyncedText = currentPasteboard
        }
        
        // Сохраняем текущее состояние счетчика буфера обмена
        lastChangeCount = NSPasteboard.general.changeCount
        
        // Запускаем постоянную проверку буфера обмена
        startMonitoringPasteboard()
    }
    
    deinit {
        // Когда объект уничтожается, останавливаем таймер, чтобы не было утечек памяти
        pasteboardTimer?.invalidate()
    }
    
    // MARK: - CBPeripheralManagerDelegate Methods
    
    // Вызывается, когда пользователь включает или выключает Bluetooth на Mac
    func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        if peripheral.state == .poweredOn {
            print("BLE на Mac включен.")
            self.powerState = .poweredOn
            setupService() // Если Bluetooth включен, настраиваем наш сервис
        } else {
            print("BLE выключен или недоступен.")
            self.powerState = .poweredOff
        }
    }

    // Настройка и создание нашего BLE-сервиса и характеристики
    private func setupService() {
        let service = CBMutableService(type: bridgerServiceUUID, primary: true)
        self.textCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        service.characteristics = [self.textCharacteristic]
        peripheralManager.add(service) // Добавляем готовый сервис в менеджер
    }
    
    // Вызывается после того, как сервис был успешно добавлен
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("Ошибка при добавлении сервиса: \(error.localizedDescription)")
            return
        }
        
        let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "McBridge";

        let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [advertiseUUID],
          CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        print("Сервис добавлен. Начало вещания с коротким UUID и именем.")
        self.connectionState = .advertising
    }

    // Вызывается, когда центральное устройство (Android) подписывается на характеристику
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Центральное устройство (Android) подключено и подписано на характеристику.")
        DispatchQueue.main.async {
            if !self.connectedDevices.contains(where: { $0.id == central.identifier }) {
                let newDevice = DeviceInfo(id: central.identifier, name: central.identifier.uuidString)
                self.connectedDevices.append(newDevice)
                self.connectionState = .connected
                self.showNotification(title: "Device Connected", body: "New device connected: \(newDevice.name)")
                print("DEBUG: Device added to connectedDevices: \(newDevice.name) (UUID: \(newDevice.id.uuidString))")
            }
        }
    }

    // Вызывается, когда центральное устройство (Android) отписывается от характеристики
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Центральное устройство (Android) отключено.")
        DispatchQueue.main.async {
            // Находим имя устройства для уведомления перед удалением
            let disconnectedDeviceName = self.connectedDevices.first(where: { $0.id == central.identifier })?.name ?? central.identifier.uuidString
            self.connectedDevices.removeAll { $0.id == central.identifier }
            if self.connectedDevices.isEmpty {
                self.connectionState = .disconnected
            }
            self.showNotification(title: "Device Disconnected", body: "Device disconnected: \(disconnectedDeviceName)")
        }
    }

    // Вызывается, когда Android присылает данные
    func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else {
            if let requestToRespond = requests.first {
                peripheral.respond(to: requestToRespond, withResult: .invalidAttributeValueLength)
            }
            return
        }

        do {
            let decoder = JSONDecoder()
            let message = try decoder.decode(Message.self, from: value)

            DispatchQueue.main.async {
                switch message.t {
                case .CLIPBOARD:
                    // Проверка на дублирование
                    guard message.p != self.lastSyncedText else {
                        print("Получен тот же текст ('\(message.p)'), игнорируем.")
                        peripheral.respond(to: request, withResult: .success)
                        return
                    }
                    
                    print("Получен текст от Android: \(message.p)")
                    self.lastSyncedText = message.p
                    self.receivedText = message.p
                    
                    self.isUpdatingInternally = true
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(message.p, forType: .string)
                    self.lastChangeCount = NSPasteboard.general.changeCount
                    self.showNotification(title: "Clipboard Synced", body: "Received from Android: \(message.p)")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        self.isUpdatingInternally = false
                    }

                case .DEVICE_NAME:
                    print("DEBUG: Received DEVICE_NAME message for central \(request.central.identifier.uuidString) with name: \(message.p)")
                    if let index = self.connectedDevices.firstIndex(where: { $0.id == request.central.identifier }) {
                        print("DEBUG: Found device at index \(index). Current name: \(self.connectedDevices[index].name)")
                        
                        // Теперь DeviceInfo - это класс ObservableObject,
                        // поэтому мы можем просто изменить его свойство name,
                        // и SwiftUI должен отреагировать.
                        self.connectedDevices[index].name = message.p
                        
                        print("DEBUG: Device name updated to \(self.connectedDevices[index].name). connectedDevices count: \(self.connectedDevices.count)")
                        // Уведомление об изменении имени устройства отключено по запросу пользователя
                    } else {
                        print("DEBUG: Received DEVICE_NAME for unknown central \(request.central.identifier.uuidString). Payload: \(message.p)")
                    }
                }
            }
        } catch {
            print("Ошибка при декодировании сообщения: \(error.localizedDescription). Полученные данные: \(String(data: value, encoding: .utf8) ?? "N/A")")
        }
        
        // Отвечаем Android, что все прошло успешно
        peripheral.respond(to: request, withResult: .success)
    }

    // MARK: - Notification Logic
    private func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { error in
            if let error = error {
                print("Error delivering notification: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Clipboard and Sending Logic
    
    /// Отправляет текст на подключенное устройство (на Android)
    func sendText(_ text: String) {
        let message = Message(t: .CLIPBOARD, p: text)
        guard let data = try? JSONEncoder().encode(message) else {
            print("Ошибка при кодировании сообщения для отправки.")
            return
        }
        
        // Отправляем текст только если Bluetooth включен, характеристика доступна и есть подключенные устройства
        if powerState == .poweredOn && textCharacteristic != nil && !connectedDevices.isEmpty {
            peripheralManager.updateValue(data, for: textCharacteristic, onSubscribedCentrals: nil)
            print("Текст отправлен на Android: \(text)")
        } else {
            print("Не удалось отправить текст: Bluetooth выключен, характеристика недоступна или нет подключенных устройств.")
        }
    }
    
    /// Запускает таймер, который будет периодически проверять буфер обмена.
    private func startMonitoringPasteboard() {
        pasteboardTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            // Каждые 0.5 секунды вызываем функцию проверки
            self?.checkPasteboard()
        }
    }
    
    /// Проверяет, изменился ли буфер обмена, и отправляет данные, если это необходимо.
    private func checkPasteboard() {
        // Если мы сами меняем буфер, ничего не делаем
        if isUpdatingInternally { return }
        
        // Если счетчик изменений в буфере не совпадает с нашим сохраненным, значит было изменение
        if NSPasteboard.general.changeCount != lastChangeCount {
            lastChangeCount = NSPasteboard.general.changeCount
            
            // Получаем новый текст из буфера
            if let newString = NSPasteboard.general.string(forType: .string) {
                
                // Проверка на дублирование
                guard newString != self.lastSyncedText else { return }

                print("Обнаружено изменение в буфере обмена Mac: \(newString)")
                // Обновляем последнее отправленное значение
                self.lastSyncedText = newString
                // Отправляем текст на Android
                sendText(newString)
            }
        }
    }
}
