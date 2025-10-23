import SwiftUI
import UserNotifications
import BluetoothService
import ClipboardService

@MainActor
class AppLogic: ObservableObject {
    @Published var model: AppViewModel?

    func setup() async {
        guard model == nil else { return }
        
        print("Starting app setup...")
        
        // 1. Create dependencies
        let bluetoothService = BluetoothManager()
        let clipboardService = ClipboardManager()

        // 2. Create the ViewModel and bind everything together
        self.model = AppViewModel(bluetoothService: bluetoothService, clipboardService: clipboardService)
        print("ViewModel created. Services are bound.")

        // 3. Request permissions
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

        // 4. Start the Clipboard service. BluetoothManager is activated in its init().
        clipboardService.start()
        print("App setup finished. ViewModel is ready.")
    }
}
