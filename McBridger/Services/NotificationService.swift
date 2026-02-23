import UserNotifications
import OSLog

public final class NotificationService: NotificationServing {
    private let logger = Logger(subsystem: "com.mcbridger.Service", category: "Notification")

    public func showNotification(title: String, body: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = UNNotificationSound.default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request) { [weak self] error in
            if let error = error {
                self?.logger.error("Error delivering notification: \(error.localizedDescription)")
            }
        }
    }
}
