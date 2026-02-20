import Foundation

extension Notification.Name {
    static let didRegisterRemoteNotificationToken = Notification.Name("didRegisterRemoteNotificationToken")
    static let didFailToRegisterRemoteNotifications = Notification.Name("didFailToRegisterRemoteNotifications")
    static let didReceiveLiveStatusWakeNotification = Notification.Name("didReceiveLiveStatusWakeNotification")
}
