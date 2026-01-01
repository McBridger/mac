import SwiftUI
import UserNotifications
import BluetoothService
import ClipboardService
import EncryptionService
import CoreModels

@MainActor
class AppLogic: ObservableObject {
    enum AppStatus: Equatable {
        case initial
        case setupRequired
        case ready
    }

    @Published var model: AppViewModel?
    @Published var status: AppStatus = .initial

    func setup() async {
        print("--- App Logic: Starting setup ---")
        
        // Bootstrap Security
        EncryptionService.shared.bootstrap(saltHex: AppConfig.encryptionSalt)
        
        if EncryptionService.shared.isReady {
            print("--- App Logic: Security is ready ---")
            self.status = .ready
        } else {
            print("--- App Logic: Security setup required. Mnemonic missing. ---")
            self.status = .setupRequired
            return 
        }
        
        if model == nil {
            // 1. Create dependencies
            let bluetoothService = BluetoothManager()
            let clipboardService = ClipboardManager()

            // 2. Create the ViewModel
            self.model = AppViewModel(bluetoothService: bluetoothService, clipboardService: clipboardService)

            // 3. Start services
            clipboardService.start()
            print("--- App Logic: Services started ---")
        }
        
        // Permissions
        Task {
            let _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])
        }
    }
    
    func finalizeSetup() {
        print("--- App Logic: Setup finalized by user ---")
        if EncryptionService.shared.isReady {
            self.status = .ready
            Task { await setup() }
        }
    }
}