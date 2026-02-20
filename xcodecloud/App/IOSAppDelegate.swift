#if os(iOS)
import Foundation
import UIKit

final class IOSAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationCenter.default.post(
            name: .didRegisterRemoteNotificationToken,
            object: nil,
            userInfo: ["deviceToken": deviceToken.hexString]
        )
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(
            name: .didFailToRegisterRemoteNotifications,
            object: error
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        NotificationCenter.default.post(
            name: .didReceiveLiveStatusWakeNotification,
            object: nil,
            userInfo: userInfo
        )
        completionHandler(.newData)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
#endif
