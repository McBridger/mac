import Factory
import Foundation
import CryptoKit

extension Container {
    var keychainManager: Factory<KeychainManaging> {
        self {
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                return MockKeychainManager()
            }
            return KeychainManager()
        }.singleton
    }

    var encryptionService: Factory<EncryptionServing> {
        self { 
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                return MockEncryptionService()
            }
            return EncryptionService()
        }.singleton
    }
    
    var bluetoothManager: Factory<BluetoothManaging> {
        self { 
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                return MockBluetoothManager()
            }
            return BluetoothManager()
        }.singleton
    }
    
    var clipboardManager: Factory<ClipboardManaging> {
        self { 
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                return MockClipboardManager()
            }
            return ClipboardManager()
        }.singleton
    }

    var notificationService: Factory<NotificationService> {
        self { NotificationService() }.singleton
    }

    var appConfig: Factory<AppConfiguring> {
        self {
            if ProcessInfo.processInfo.arguments.contains("--uitesting") {
                return MockAppConfig()
            }
            return AppConfig()
        }.singleton
    }

    var appLogic: Factory<AppLogic> {
        self { AppLogic() }.singleton
    }
}
