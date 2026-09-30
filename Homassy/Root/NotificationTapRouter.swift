import CoreLocation
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

/// Routes notification taps and shows banners while the app is open (expiry summaries and store reminders).
/// A tap opens where its items are (user choice A, 2026-09-26): expiry summaries the Inventory tab, store reminders
/// the Shopping tab, on the space with most of the items. HomassyCore decides (`NotificationActions`), and
/// `AppRouter` opens it. N-02 decision 2A: no notification buttons.
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
        let destination = NotificationActions.destination(actionIdentifier: response.actionIdentifier,
                                                          requestIdentifier: request.identifier,
                                                          spaceID: NotificationActions.spaceID(in: request.content.userInfo))
        let branch = Self.arrivalBranch(of: request)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                if let branch { AppRouter.shared.arrivalBranch = branch }
                if let destination { AppRouter.shared.open(destination) }
            }
            completionHandler()
        }
    }

    /// A store reminder's chain and circle (P4-06), for the shopping Live Activity (N-04). Pure, any thread.
    nonisolated static func arrivalBranch(of request: UNNotificationRequest) -> ChainBranch? {
        guard let key = StoreReminderPlanner.chainKey(fromIdentifier: request.identifier),
              let trigger = request.trigger as? UNLocationNotificationTrigger,
              let region = trigger.region as? CLCircularRegion else { return nil }
        return ChainBranch(chainKey: key, center: Coordinate(latitude: region.center.latitude,
                                                             longitude: region.center.longitude))
    }
}
