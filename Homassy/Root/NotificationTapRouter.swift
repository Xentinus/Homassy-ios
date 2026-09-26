import Observation
import UserNotifications

/// The Settings app switch (`Settings.bundle`, key `storeRemindersEnabled`, default on, P4-06).
enum StoreReminderSettings {
    static let key = "storeRemindersEnabled"

    /// Settings bundle defaults are not applied until the user opens the page, so the app registers its own.
    static func registerDefault() {
        UserDefaults.standard.register(defaults: [key: true])
    }

    static var isEnabled: Bool { UserDefaults.standard.bool(forKey: key) }
}

/// A tapped store reminder opens the Shopping tab.
@MainActor
@Observable
final class NotificationTapRouter {
    static let shared = NotificationTapRouter()
    var pendingTab: AppTab?
}

/// Routes notification taps and shows banners while the app is open (expiry summaries and store reminders).
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationResponder()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let identifier = response.notification.request.identifier
        guard identifier.hasPrefix("store-") || identifier.hasPrefix("preview-store-") else { return }
        await MainActor.run { NotificationTapRouter.shared.pendingTab = .shopping }
    }
}
