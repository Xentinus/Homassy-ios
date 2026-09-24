import Foundation
import Observation

/// The five pages of spec §6.9, in order.
public enum IntroductionPage: Int, CaseIterable, Identifiable, Sendable {
    case welcome, inventory, shopping, spaces, notifications
    public var id: Int { rawValue }
}

/// First-launch introduction. Shown once; finishing or skipping hides it for good.
@MainActor
@Observable
public final class IntroductionModel {
    public static let defaultsKey = "hasSeenIntroduction"

    public private(set) var hasSeenIntroduction: Bool
    public var currentPage: IntroductionPage = .welcome

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let notifications: any NotificationAuthorizing
    @ObservationIgnored private var hasRequestedPermission = false

    public init(defaults: UserDefaults = .standard, notifications: any NotificationAuthorizing) {
        self.defaults = defaults
        self.notifications = notifications
        hasSeenIntroduction = defaults.bool(forKey: Self.defaultsKey)
    }

    public var shouldShow: Bool { !hasSeenIntroduction }

    public var isOnLastPage: Bool { currentPage == IntroductionPage.allCases.last }

    public func next() {
        if let following = IntroductionPage(rawValue: currentPage.rawValue + 1) {
            currentPage = following
        }
    }

    /// "Skip": hides the introduction without the notification prompt.
    public func skip() {
        markSeen()
    }

    /// "Get started": hides the introduction, then asks for notification permission once.
    /// The answer does not matter; declining changes nothing else in the app.
    public func finish() async {
        let wasShowing = !hasSeenIntroduction
        markSeen()
        guard wasShowing, !hasRequestedPermission else { return }
        hasRequestedPermission = true
        _ = try? await notifications.requestAuthorization()
    }

    private func markSeen() {
        hasSeenIntroduction = true
        defaults.set(true, forKey: Self.defaultsKey)
    }
}
