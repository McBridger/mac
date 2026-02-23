import Foundation

public protocol NotificationServing: Sendable {
    func showNotification(title: String, body: String)
}
