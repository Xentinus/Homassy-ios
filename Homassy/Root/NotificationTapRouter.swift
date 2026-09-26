import Foundation
import HomassyCore
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

/// A tapped notification opens where its items are (user choice A, 2026-09-26): expiry summaries the Inventory
/// tab, store reminders the Shopping tab, on the space with most of the items.
@MainActor
@Observable
final class NotificationTapRouter {
    static let shared = NotificationTapRouter()
    var pendingTab: AppTab?
    var pendingSpaceID: UUID?

    /// The tab for a notification identifier ("preview-" copies from the DEBUG preview count too).
    nonisolated static func tab(for identifier: String) -> AppTab? {
        let id = identifier.hasPrefix("preview-") ? String(identifier.dropFirst("preview-".count)) : identifier
        if id.hasPrefix("store-") { return .shopping }
        if id.hasPrefix("daily-") || id.hasPrefix("weekly-") { return .inventory }
        return nil
    }
}

/// Routes notification taps and shows banners while the app is open (expiry summaries and store reminders).
final class NotificationResponder: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    static let shared = NotificationResponder()

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let request = response.notification.request
        guard let tab = NotificationTapRouter.tab(for: request.identifier) else { return }
        let space = (request.content.userInfo[SystemNotificationCenter.spaceIDKey] as? String).flatMap(UUID.init(uuidString:))
        await MainActor.run {
            NotificationTapRouter.shared.pendingSpaceID = space
            NotificationTapRouter.shared.pendingTab = tab
        }
    }
}
