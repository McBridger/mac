import Factory
import Foundation
import CryptoKit

extension Container {
    var encryptionService: Factory<EncryptionService> {
        self { EncryptionService() }.singleton
    }
    
    var bluetoothManager: Factory<BluetoothManager> {
        self { BluetoothManager() }
    }
    
    var clipboardManager: Factory<ClipboardManager> {
        self { ClipboardManager() }.singleton
    }

    var notificationService: Factory<NotificationService> {
        self { NotificationService() }.singleton
    }

    var appLogic: Factory<AppLogic> {
        self { AppLogic() }.singleton
    }
}
