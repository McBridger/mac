#if DEBUG
import Foundation

public enum TestNotification: String {
    case connectDevice = "com.mcbridger.test.connect_device"
    case introduceDevice = "com.mcbridger.test.introduce_device"
    case connectAndIntroduceDevice = "com.mcbridger.test.connect_and_introduce"
    case receiveData = "com.mcbridger.test.receive_data"
    case simulateIncomingTiny = "com.mcbridger.test.simulate_incoming_tiny"
    case dataSent = "com.mcbridger.test.data_sent"
    case simulateClipboardChange = "com.mcbridger.test.simulate_clipboard_change"
    case simulateFileCopy = "com.mcbridger.test.simulate_file_copy"
    case clipboardSetLocally = "com.mcbridger.test.clipboard_set_locally"
    case fileSetLocally = "com.mcbridger.test.file_set_locally"
    
    public var name: NSNotification.Name {
        NSNotification.Name(self.rawValue)
    }
}

extension Notification {
    /// Decodes a JSON dictionary from the notification's 'object' string.
    /// Used because DistributedNotificationCenter userInfo is unreliable in Sandbox.
    public var testPayload: [String: Any]? {
        guard let jsonString = object as? String,
              let data = jsonString.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }
}
#endif