import Foundation
import CoreBluetooth
import SystemConfiguration
import OSLog
import CoreModels

// Протокол для общения с внешним миром (читай: с твоим SwiftUI View)
// Делаем его @MainActor, чтобы не было сюрпризов при обновлении UI.
@MainActor
protocol BluetoothManagerDelegate: AnyObject, Sendable {
    func powerStateChanged(to state: BluetoothPowerState)
    func connectionStateChanged(to state: ConnectionState)
    func deviceListUpdated(devices: [DeviceInfo])
}

// Вот он, наш монстр. Один, чтобы править всеми.
public actor BluetoothManager: NSObject {
    
    // MARK: - Public State & Delegate
    
    weak var delegate: BluetoothManagerDelegate?
    
    // Состояние, которое раньше было размазано по двум акторам
    private(set) var powerState: BluetoothPowerState = .poweredOff
    private(set) var connectionState: ConnectionState = .disconnected
    
    // А вот и наша каноничная мапа с устройствами. Раньше жила в хендлере.
    private var devices: [UUID: DeviceInfo] = [:]
    
    // MARK: - CoreBluetooth Properties
    
    private var peripheralManager: CBPeripheralManager!
    private var textCharacteristic: CBMutableCharacteristic?
    
    // Твои UUID, не трогаем, святое.
    private let advertiseUUID = CBUUID(string: "fdd2")
    private let bridgerServiceUUID = CBUUID(string: "ccfa23b4-ba6f-448a-827d-c25416ec432e")
    private let characteristicUUID = CBUUID(string: "315eca9d-0dbc-498d-bb4d-1d59d7c5bc3b")

    // MARK: - Device Handling Logic (from DeviceConnectionHandler)
    
    // Таски для отслеживания таймаутов. Если девайс подключился, но не представился - в утиль.
    private var nameRequestTasks: [UUID: Task<Void, Never>] = [:]
    private let nameRequestTimeout: TimeInterval = 5.0
    
    // Задача для отложенного обновления UI. Чтобы не спамить его на каждое мелкое изменение.
    private var reportingTask: Task<Void, Never>?

    // MARK: - Lifecycle
    
    public override init() {
        super.init()
        // Создаём очередь и менеджера. Классика.
        let queue = DispatchQueue(label: "com.mcbridge.bluetooth-god-queue")
        self.peripheralManager = CBPeripheralManager(delegate: self, queue: queue)
    }
    
    // MARK: - Public API
    
    public func send(message: BridgerMessage) {
        // Этот метод почти не изменился. Простая отправка данных.
        guard let data = try? message.toData() else {
            Logger.bluetooth.error("Не шмогла закодировать сообщение в дату. Говно какое-то.")
            return
        }
        
        if powerState == .poweredOn, let characteristic = textCharacteristic, !devices.isEmpty {
            peripheralManager.updateValue(data, for: characteristic, onSubscribedCentrals: nil)
            Logger.bluetooth.info("Отправил сообщение типа \(message.type.rawValue).")
        }
    }
    
    // MARK: - Internal Logic (The Merged Part)
    
    private func handleStateUpdate(to bleState: CBManagerState) {
        let newState: BluetoothPowerState = (bleState == .poweredOn) ? .poweredOn : .poweredOff
        guard self.powerState != newState else { return }
        
        self.powerState = newState
        Logger.bluetooth.info("Состояние блюпупа изменилось: \(newState.rawValue)")
        
        Task { await delegate?.powerStateChanged(to: newState) }
        
        if newState == .poweredOn {
            setupService()
        } else {
            // Если блютуз отвалился, чистим всё к чертям
            devices.removeAll()
            connectionState = .disconnected
            reportUpdatedDeviceListDebounced()
            Task { await delegate?.connectionStateChanged(to: .disconnected) }
        }
    }
    
    private func setupService() {
        // Как было, так и осталось. Настраиваем сервис и характеристику.
        let service = CBMutableService(type: bridgerServiceUUID, primary: true)
        self.textCharacteristic = CBMutableCharacteristic(
            type: characteristicUUID,
            properties: [.read, .write, .notifyEncryptionRequired],
            value: nil,
            permissions: [.readEncryptionRequired, .writeEncryptionRequired]
        )
        service.characteristics = [self.textCharacteristic!]
        peripheralManager.add(service)
    }

    private func startAdvertising() {
        guard connectionState != .advertising else { return }
        
        let deviceName = SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "McBridge"
        let advertisementData: [String: Any] = [
          CBAdvertisementDataServiceUUIDsKey: [advertiseUUID],
          CBAdvertisementDataLocalNameKey: deviceName
        ]
        
        peripheralManager.startAdvertising(advertisementData)
        self.connectionState = .advertising
        Logger.bluetooth.info("Начал орать в эфир с погонялом \(deviceName).")
        
        Task { await delegate?.connectionStateChanged(to: .advertising) }
    }
    
    private func handleSubscription(from centralId: UUID) {
        guard devices[centralId] == nil else {
            Logger.bluetooth.warning("Какой-то хер (\(centralId.uuidString)) пытается подключиться второй раз. Игнор.")
            return
        }
        
        // Добавляем ноунейма в список и запускаем таймер на получение имени
        let newDevice = DeviceInfo(id: centralId, name: "Неизвестный солдат...")
        devices[centralId] = newDevice
        connectionState = .connected
        
        Logger.bluetooth.info("Подключился анонимус: \(centralId.uuidString). Ждём, пока представится.")
        
        // Запускаем таску-сторожа
        nameRequestTasks[centralId] = Task {
            do {
                try await Task.sleep(for: .seconds(nameRequestTimeout))
                // Если мы дошли до сюда, значит девайс так и не прислал имя.
                await handleDeviceTimeout(centralId)
            } catch {
                // Таску отменили, значит всё ок, имя пришло вовремя.
            }
        }
        
        reportUpdatedDeviceListDebounced()
        Task { await delegate?.connectionStateChanged(to: .connected) }
    }
    
    private func handleUnsubscription(from centralId: UUID) {
        if let disconnectedDevice = devices[centralId] {
            devices.removeValue(forKey: centralId)
            nameRequestTasks[centralId]?.cancel() // Отменяем таймаут, он больше не нужен
            nameRequestTasks.removeValue(forKey: centralId)
            
            Logger.bluetooth.info("Устройство \(disconnectedDevice.name) (\(centralId.uuidString)) свалило в закат.")

            if devices.isEmpty {
                connectionState = .disconnected
                Task { await delegate?.connectionStateChanged(to: .disconnected) }
            }
            
            reportUpdatedDeviceListDebounced()
        }
    }
    
    private func handleWrite(value: Data, from centralID: UUID) {
        do {
            let message = try BridgerMessage.fromData(value, address: centralID.uuidString)
            Logger.bluetooth.info("Получено сообщение типа \(message.type.rawValue) от \(centralID.uuidString)")
            
            // А вот и сама логика, которая раньше жила в хендлере
            switch message.type {
            case .DEVICE_NAME:
                handleDeviceNamed(id: centralID, name: message.value)
            // тут могут быть другие кейсы
            default:
                Logger.bluetooth.info("Получил какое-то непонятное сообщение типа \(message.type.rawValue), забил.")
            }
            
        } catch {
            Logger.bluetooth.error("Ошибка декодирования, прислали какую-то дичь: \(error.localizedDescription)")
        }
    }
    
    private func handleDeviceNamed(id: UUID, name: String) {
        guard devices[id] != nil else {
            Logger.bluetooth.warning("Получил имя '\(name)' от уже отвалившегося девайса \(id). Поздно, поезд ушел.")
            return
        }
        
        // Девайс представился, отменяем таймаут на его удаление
        nameRequestTasks[id]?.cancel()
        nameRequestTasks.removeValue(forKey: id)
        
        // Обновляем инфу
        let updatedDevice = DeviceInfo(id: id, name: name)
        devices[id] = updatedDevice
        Logger.bluetooth.info("Анонимус \(id) оказался \(name). Приятно познакомиться.")
        
        // Сообщаем UI
        reportUpdatedDeviceListDebounced()
    }
    
    private func handleDeviceTimeout(_ deviceId: UUID) {
        // Эта функция вызывается, если таска-сторож дожила до конца
        guard devices[deviceId] != nil else { return }
        
        Logger.bluetooth.warning("Таймаут для устройства \(deviceId.uuidString). Так и не представился, мразь. Удаляем.")
        devices.removeValue(forKey: deviceId)
        nameRequestTasks.removeValue(forKey: deviceId)
        reportUpdatedDeviceListDebounced()
    }

    private func reportUpdatedDeviceListDebounced() {
        // Старый добрый дебаунсер. Отменяем старую таску, создаем новую.
        reportingTask?.cancel()
        
        reportingTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(100))
                let deviceList = Array(devices.values).sorted { $0.name < $1.name }
                Logger.bluetooth.debug("Отправляем в UI обновленный список: \(deviceList.count) устройств")
                await self.delegate?.deviceListUpdated(devices: deviceList)
            } catch {
                // Попали сюда, если таску отменили. Ничего не делаем, это норма.
            }
        }
    }
}

// MARK: - CBPeripheralManagerDelegate

extension BluetoothManager: CBPeripheralManagerDelegate {
    
    // Делегатные методы теперь - просто тонкие трамплины в наш актор.
    // Они в nonisolated контексте, поэтому оборачиваем вызовы в Task.
    
    public nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        let state = peripheral.state
        Task { await handleStateUpdate(to: state) }
    }

    public nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        if let error = error {
            Logger.bluetooth.error("Ошибка при добавлении сервиса: \(error.localizedDescription)")
            return
        }
        Task { await startAdvertising() }
    }

    public nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didSubscribeTo characteristic: CBCharacteristic) {
        let centralID = central.identifier
        Task { await handleSubscription(from: centralID) }
    }

    public nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, central: CBCentral, didUnsubscribeFrom characteristic: CBCharacteristic) {
        let centralID = central.identifier
        Task { await handleUnsubscription(from: centralID) }
    }

    public nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didReceiveWrite requests: [CBATTRequest]) {
        guard let request = requests.first, let value = request.value else { return }

        let centralID = request.central.identifier

        Task { await handleWrite(value: value, from: centralID) }
        
        peripheral.respond(to: request, withResult: .success)
    }
}


// Удобное расширение для логгера, как и было
extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier!
    static let bluetooth = Logger(subsystem: subsystem, category: "BluetoothManager")
}