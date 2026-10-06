import Foundation
import UserNotifications

/// Asks the user for notification permission. Faked in tests and UI tests.
public protocol NotificationAuthorizing: Sendable {
    func requestAuthorization() async throws -> Bool
}

/// The real prompt: alerts, badge and sound, matching what the daily summary and badge need (spec §6.5).
public struct UserNotificationAuthorizer: NotificationAuthorizing {
    public init() {}

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
    }
}
