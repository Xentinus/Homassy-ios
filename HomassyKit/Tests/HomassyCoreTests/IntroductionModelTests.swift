import Foundation
import Testing
@testable import HomassyCore

actor FakeNotificationAuthorizer: NotificationAuthorizing {
    private(set) var requests = 0
    private let granted: Bool
    private let fails: Bool

    init(granted: Bool = true, fails: Bool = false) {
        self.granted = granted
        self.fails = fails
    }

    func requestAuthorization() async throws -> Bool {
        requests += 1
        if fails { throw CocoaError(.featureUnsupported) }
        return granted
    }
}

@MainActor
@Suite("IntroductionModel")
struct IntroductionModelTests {
    private func freshDefaults() -> UserDefaults {
        let suite = "IntroductionModelTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// P1-10a (user pick 2026-09-26): free comes right after welcome, privacy right before notifications;
    /// notifications stays last, because Get started asks for the notification permission.
    @Test func hasSevenPagesInSpecOrder() {
        #expect(IntroductionPage.allCases == [.welcome, .free, .inventory, .shopping, .spaces, .privacy, .notifications])
    }

    @Test func showsOnFirstLaunch() {
        let model = IntroductionModel(defaults: freshDefaults(), notifications: FakeNotificationAuthorizer())
        #expect(model.shouldShow)
        #expect(model.currentPage == .welcome)
        #expect(!model.isOnLastPage)
    }

    @Test func nextWalksToTheLastPageAndStops() {
        let model = IntroductionModel(defaults: freshDefaults(), notifications: FakeNotificationAuthorizer())
        for _ in 0..<10 { model.next() }
        #expect(model.currentPage == .notifications)
        #expect(model.isOnLastPage)
    }

    @Test func finishPersistsAndNeverShowsAgain() async {
        let defaults = freshDefaults()
        let model = IntroductionModel(defaults: defaults, notifications: FakeNotificationAuthorizer())
        await model.finish()

        #expect(!model.shouldShow)
        #expect(defaults.bool(forKey: "hasSeenIntroduction"))
        let relaunched = IntroductionModel(defaults: defaults, notifications: FakeNotificationAuthorizer())
        #expect(!relaunched.shouldShow)
    }

    @Test func skipPersistsWithoutAskingForPermission() async {
        let defaults = freshDefaults()
        let notifications = FakeNotificationAuthorizer()
        let model = IntroductionModel(defaults: defaults, notifications: notifications)
        model.skip()

        #expect(!model.shouldShow)
        #expect(defaults.bool(forKey: "hasSeenIntroduction"))
        #expect(await notifications.requests == 0)
        #expect(!IntroductionModel(defaults: defaults, notifications: notifications).shouldShow)
    }

    @Test func finishAsksForPermissionExactlyOnce() async {
        let notifications = FakeNotificationAuthorizer()
        let model = IntroductionModel(defaults: freshDefaults(), notifications: notifications)
        async let first: Void = model.finish()
        async let second: Void = model.finish()
        _ = await (first, second)
        await model.finish()

        #expect(await notifications.requests == 1)
    }

    @Test func declinedOrFailedPermissionStillFinishes() async {
        for notifications in [FakeNotificationAuthorizer(granted: false), FakeNotificationAuthorizer(fails: true)] {
            let defaults = freshDefaults()
            let model = IntroductionModel(defaults: defaults, notifications: notifications)
            await model.finish()
            #expect(!model.shouldShow)
            #expect(defaults.bool(forKey: "hasSeenIntroduction"))
        }
    }

    @Test func alreadySeenNeverAsks() async {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "hasSeenIntroduction")
        let notifications = FakeNotificationAuthorizer()
        let model = IntroductionModel(defaults: defaults, notifications: notifications)

        #expect(!model.shouldShow)
        await model.finish()
        #expect(await notifications.requests == 0)
    }
}
