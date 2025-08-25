import Foundation
import CoreBluetooth
import Combine
import AppKit // Импорт для работы с буфером обмена NSPasteboard
// Класс управляет всей логикой Bluetooth и синхронизацией буфера обмена.
// NSObject - требование для делегатов CoreBluetooth.
// ObservableObject - чтобы SwiftUI мог следить за его изменениями.
// CBPeripheralManagerDelegate - чтобы получать события от Bluetooth-модуля.
class BLEPeripheralManager: NSObject, ObservableObject, CBPeripheralManagerDelegate {
    // MARK: - Published Properties for SwiftUI
    // Эти свойства будут автоматически обновлять интерфейс
    @Published var receivedText: String = "Ожидание данных от Android..."
    @Published var isPoweredOn: Bool = false
    @Published var connectionStatus: String = "Disconnected"

    // MARK: - BLE Properties
    private var peripheralManager: CBPeripheralManager!
    private var textCharacteristic: CBMutableCharacteristic!
    private var macToAndroidCharacteristic: CBMutableCharacteristic!
    // Эти UUID должны быть точно такими же, как и в Android-приложении
    let bridgerServiceUUID = CBUUID(string: "81a936be-a052-4ef1-9c3c-073c0b63438d")
    let AndroidToMacCharacteristicUUID = CBUUID(string: "f95f7d8b-cd6d-433a-b1d1-28b0955faa52")
    let MacToAndroidCharacteristicUUID = CBUUID(string: "b184c753-e5ca-401c-9844-b3935a56b7d2")
    
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
            self.isPoweredOn = true
            setupService() // Если Bluetooth включен, настраиваем наш сервис
        } else {
            print("BLE выключен или недоступен.")
            self.isPoweredOn = false
        }
    }

    // Настройка и создание нашего BLE-сервиса и характеристики
    private func setupService() {
        let service = CBMutableService(type: bridgerServiceUUID, primary: true)
        textCharacteristic = CBMutableCharacteristic(
            type: AndroidToMacCharacteristicUUID,
            properties: [.read, .write, .notify], // Позволяем читать, писать и получать уведомления
            value: nil,
            permissions: [.readable, .writeable] // Даем права на чтение и запись
        )
        macToAndroidCharacteristic = CBMutableCharacteristic(
            type: MacToAndroidCharacteristicUUID,
            properties: [.notify, .read], // Android будет читать/подписываться на эту характеристику
            value: nil,
            permissions: [.readable] // Даем права на чтение
        )
        service.characteristics = [textCharacteristic, macToAndroidCharacteristic]
        peripheralManager.add(service) // Добавляем готовый сервис в менеджер
    }
    
    // Вызывается после того, как сервис был успешно добавлен
    func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            print("Ошибка при добавлении сервиса: \(error.localizedDescription)")
            return
        }
        
        // let deviceName = Host.current().localizedName ?? "Mac Bridger"
        let deviceName = "McBridge"

        let advertisementData: [String: Any] = [
            CBAdvertisementDataLocalNameKey: deviceName,
            CBAdvertisementDataServiceUUIDsKey: [service.uuid]
        ]
        peripheralManager.startAdvertising(advertisementData)
        print("Сервис добавлен. Начало вещания.")
        self.connectionStatus = "Advertising"
    }

    // Вызывается, когда центральное устройство (Android) подписывается на характеристику
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        print("Центральное устройство (Android) подключено и подписано на характеристику.")
        DispatchQueue.main.async {
            self.connectionStatus = "Connected to Android"
        }
    }

    // Вызывается, когда центральное устройство (Android) отписывается от характеристики
    func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        print("Центральное устройство (Android) отключено.")
        DispatchQueue.main.async {
            self.connectionStatus = "Disconnected"
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

        if let receivedString = String(data: value, encoding: .utf8) {
            
            // Проверка на дублирование
            guard receivedString != self.lastSyncedText else {
                print("Получен тот же текст ('\(receivedString)'), игнорируем.")
                peripheral.respond(to: request, withResult: .success)
                return
            }
            
            print("Получен текст от Android: \(receivedString)")
            
            // Обновляем UI и буфер обмена в главном потоке
            DispatchQueue.main.async {
                self.lastSyncedText = receivedString
                self.receivedText = receivedString
                
                // Устанавливаем флаг, чтобы разорвать цикл
                self.isUpdatingInternally = true
                
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(receivedString, forType: .string)
                self.lastChangeCount = NSPasteboard.general.changeCount
                
                // Показываем уведомление
                self.showNotification(title: "Clipboard Synced", body: "Received from Android: \(receivedString)")
                
                // Сбрасываем флаг с небольшой задержкой
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.isUpdatingInternally = false
                }
            }
        }
        
        // Отвечаем Android, что все прошло успешно
        peripheral.respond(to: request, withResult: .success)
    }

    // MARK: - Notification Logic
    private func showNotification(title: String, body: String) {
        let notification = NSUserNotification()
        notification.title = title
        notification.informativeText = body
        notification.deliveryDate = Date() // Deliver immediately
        
        NSUserNotificationCenter.default.deliver(notification)
    }

    // MARK: - Clipboard and Sending Logic
    
    /// Отправляет текст на подключенное устройство (на Android)
    func sendText(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        if isPoweredOn && macToAndroidCharacteristic != nil {
            peripheralManager.updateValue(data, for: macToAndroidCharacteristic, onSubscribedCentrals: nil)
            print("Текст отправлен на Android: \(text)")
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
