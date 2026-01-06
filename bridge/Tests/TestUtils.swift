#if DEBUG
import Foundation

/// Helper to ensure consistent notification names across test runner and app
public enum TestNotification {
    public static let connectDevice = "com.mcbridger.test.connect_device"
    public static let receiveData = "com.mcbridger.test.receive_data"
    public static let dataSent = "com.mcbridger.test.data_sent"
    public static let simulateClipboardChange = "com.mcbridger.test.simulate_clipboard_change"
    public static let clipboardSetLocally = "com.mcbridger.test.clipboard_set_locally"
}
#endif