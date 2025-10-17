import SwiftUI
import UserNotifications
import BluetoothService
import ClipboardService

@MainActor // Гарантирует, что все обновления @Published происходят в главном потоке
class AppLogic: ObservableObject {
    @Published var model: AppViewModel?

    // Асинхронная функция, которая выполняет всю тяжелую работу
    func setup() async {
        // Убедимся, что не запускаем настройку дважды
        guard model == nil else { return }
        
        print("Starting app setup...")
        
        // 1. Создаем зависимости
        let bluetoothService = BluetoothManager()
        let clipboardService = ClipboardManager()

        // 2. Создаем ViewModel и связываем все вместе
        self.model = AppViewModel(bluetoothService: bluetoothService, clipboardService: clipboardService)
        print("ViewModel created. Services are bound.")

        // 3. Запрашиваем разрешения
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                print("Notification permissions granted.")
            } else {
                print("Notification permissions denied.")
            }
        } catch {
            print("Notification permissions request failed: \(error.localizedDescription)")
        }

        // 4. Запускаем Clipboard сервис. BluetoothManager активируется в init().
        clipboardService.start()
        print("App setup finished. ViewModel is ready.")
    }
}
