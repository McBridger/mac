import Factory
import Foundation
import CryptoKit

extension Container {
    var keychainManager: Factory<KeychainManaging> {
        self { KeychainManager() }.singleton
    }

    var encryptionService: Factory<EncryptionServing> {
        self { EncryptionService() }.singleton
    }
    
    var bluetoothManager: Factory<BluetoothManaging> {
        self { BluetoothManager() }.singleton
    }
    
    var bleDriver: Factory<BLEDriverProtocol> {
        self { BLEDriver() }.singleton
    }
    
    var clipboardManager: Factory<ClipboardManaging> {
        self { ClipboardManager() }.singleton
    }

    var notificationService: Factory<NotificationService> {
        self { NotificationService() }.singleton
    }

    var appConfig: Factory<AppConfiguring> {
        self { AppConfig() }.singleton
    }

    var appLogic: Factory<AppLogic> {
        self { AppLogic() }.singleton
    }

    var tcpFileProvider: Factory<TcpFileProviding> {
        self { TcpFileProvider() }.singleton
    }

    var tcpManager: Factory<TcpManaging> {
        self { TcpManager() }.singleton
    }
}