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

    // Completion-handler forms on purpose: the async forms finish on a background thread, and UIKit then aborts
    // (`_performBlockAfterCATransactionCommitSynchronizes` assertion, seen on the iPhone 2026-09-26). The handlers are
    // always called on the main thread.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping @Sendable (UNNotificationPresentationOptions) -> Void) {
        DispatchQueue.main.async { completionHandler([.banner, .list, .sound]) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping @Sendable () -> Void) {
        let request = response.notification.request
        let tab = NotificationTapRouter.tab(for: request.identifier)
        let space = (request.content.userInfo[SystemNotificationCenter.spaceIDKey] as? String).flatMap(UUID.init(uuidString:))
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let tab {
                    NotificationTapRouter.shared.pendingSpaceID = space
                    NotificationTapRouter.shared.pendingTab = tab
                }
            }
            completionHandler()
        }
    }
}
