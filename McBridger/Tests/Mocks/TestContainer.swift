#if DEBUG
import Foundation
import Factory

public struct TestContainer {
    public static func mock(shouldMock: Bool) {
        guard shouldMock else { return }
        Container.shared.keychainManager.register { MockKeychainManager() }
        Container.shared.encryptionService.register { MockEncryptionService() }
        Container.shared.bleDriver.register { MockBLEDriver() }
        Container.shared.clipboardManager.register { MockClipboardManager() }
        Container.shared.appConfig.register { MockAppConfig() }
        print("--- UI Testing Mode: Mocks Registered via TestContainer ---")
    }
}
#endif
