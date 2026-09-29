import Foundation
import Testing
import UserNotifications
@testable import HomassyCore

@Suite("Notification actions")
struct NotificationActionsTests {
    let space = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!

    func destination(_ action: String, _ request: String) -> AppDestination? {
        NotificationActions.destination(actionIdentifier: action, requestIdentifier: request, spaceID: space)
    }

    @Test func summaryTapOpensInventoryOnItsSpace() {
        #expect(destination(UNNotificationDefaultActionIdentifier, "daily-2026-10-01") == .inventory(spaceID: space))
        #expect(destination(UNNotificationDefaultActionIdentifier, "weekly-2026-10-05") == .inventory(spaceID: space))
        #expect(destination(UNNotificationDefaultActionIdentifier, "preview-daily-2026-10-01") == .inventory(spaceID: space))
    }

    @Test func storeReminderTapOpensShopping() {
        #expect(destination(UNNotificationDefaultActionIdentifier, "store-auchan-0") == .shopping(spaceID: space))
        #expect(destination(UNNotificationDefaultActionIdentifier, "preview-store-auchan-0") == .shopping(spaceID: space))
    }

    @Test func dismissAndForeignRequestsAreIgnored() {
        #expect(destination(UNNotificationDismissActionIdentifier, "daily-2026-10-01") == nil)
        #expect(destination(UNNotificationDefaultActionIdentifier, "backup-reminder") == nil)
    }

    @Test func categoriesFollowTheIdentifierPrefix() {
        #expect(NotificationActions.category(forIdentifier: "daily-2026-10-01") == NotificationActions.expiryCategory)
        #expect(NotificationActions.category(forIdentifier: "weekly-2026-10-05") == NotificationActions.expiryCategory)
        #expect(NotificationActions.category(forIdentifier: "preview-daily-2026-10-01") == NotificationActions.expiryCategory)
        #expect(NotificationActions.category(forIdentifier: "store-auchan-0") == NotificationActions.storeCategory)
        #expect(NotificationActions.category(forIdentifier: "preview-store-auchan-0") == NotificationActions.storeCategory)
        #expect(NotificationActions.category(forIdentifier: "other") == nil)
    }

    @Test func spaceIDParsing() {
        #expect(NotificationActions.spaceID(in: [SystemNotificationCenter.spaceIDKey: space.uuidString]) == space)
        #expect(NotificationActions.spaceID(in: [SystemNotificationCenter.spaceIDKey: "not-a-uuid"]) == nil)
        #expect(NotificationActions.spaceID(in: [:]) == nil)
    }

    /// Decision 2A (2026-09-29): no custom buttons, a long press shows only the content.
    @Test func categoriesHaveNoButtons() {
        let categories = NotificationActions.categories()
        #expect(Set(categories.map(\.identifier)) == [NotificationActions.expiryCategory, NotificationActions.storeCategory])
        #expect(categories.allSatisfy { $0.actions.isEmpty })
    }
}
