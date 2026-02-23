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

    var broker: Factory<Broker> {
        self { Broker() }.singleton
    }

    var blobStorageManager: Factory<BlobStorageManaging> {
        self { BlobStorageManager() }.singleton
    }

    var tcpManager: Factory<TcpManaging> {
        self { TcpManager() }.singleton
    }
    
    var lifecycleObserver: Factory<AppLifecycleObserving> {
        self { LifecycleObserver() }.singleton
    }
    
    var systemObserver: Factory<SystemObserving> {
        self { SystemObserver(lifecycle: self.lifecycleObserver()) }.singleton
    }
    
    var wakeManager: Factory<WakeManaging> {
        self { WakeManager() }.singleton
    }
    
    var historyManager: Factory<HistoryManaging> {
        self { HistoryManager() }.singleton
    }
}