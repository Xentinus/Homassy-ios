#if DEBUG
import CloudKit
import Foundation
import HomassyCore

/// Launch-argument switches used only by HomassyUITests. Compiled out of release builds.
enum UITestHooks {
    nonisolated static let userRecordName = "_uiTestUser"

    /// `-uiTestAccountState available|noAccount|restricted|temporarilyUnavailable|couldNotDetermine`
    static var accountState: AccountState? {
        switch value(after: "-uiTestAccountState") {
        case "available": .available
        case "noAccount": .noAccount
        case "restricted": .restricted
        case "temporarilyUnavailable": .temporarilyUnavailable
        case "couldNotDetermine": .couldNotDetermine
        default: nil
        }
    }

    /// `-resetIntroduction`: forget that the introduction was seen, so it shows on this launch.
    static var resetIntroduction: Bool { contains("-resetIntroduction") }

    /// True whenever the app was launched by a UI test.
    static var isActive: Bool { accountState != nil }

    /// `-uiTestAttribution`: after seeding, pretend someone else just changed Milk, with a long window
    /// so a UI test can see the ring and the "· now" caption (P5-04). Nothing else arrives from others locally.
    static var simulatesAttribution: Bool { contains("-uiTestAttribution") }

    /// `-uiTestSyncProblem`: feed the sync status one "iCloud storage full" failure, which is persistent at once,
    /// so a UI test sees the space menu's red dot and the settings callout (P5-05). Local stores post no CloudKit
    /// events.
    static var simulatesSyncProblem: Bool { contains("-uiTestSyncProblem") }

    /// UI tests start every launch on Inventory with empty stacks: the scene delegate lets the system
    /// restore scene storage across test launches, which would leak the previous test's tab.
    static var ignoresRestoredSceneState: Bool { isActive }

    static func contains(_ flag: String) -> Bool {
        ProcessInfo.processInfo.arguments.contains(flag)
    }

    private static func value(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}

/// Answers with a fixed account state instead of asking CloudKit.
nonisolated struct UITestAccountStatus: AccountStatusProviding {
    let state: AccountState

    func accountStatus() async throws -> CKAccountStatus {
        switch state {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .checking, .couldNotDetermine: .couldNotDetermine
        }
    }

    func userRecordName() async throws -> String {
        UITestHooks.userRecordName
    }
}
/// Schedules nothing and leaves the badge alone during UI tests (P2-10).
nonisolated struct UITestNotificationCenter: NotificationCentering {
    func pendingRequestIdentifiers() async -> [String] { [] }
    func add(_ notification: PlannedNotification) async throws {}
    func removePendingRequests(withIdentifiers identifiers: [String]) async {}
    func setBadgeCount(_ count: Int) async throws {}
    func addLocation(_ reminder: PlannedStoreReminder) async throws {}
}

/// Never shows the system prompt during UI tests.
nonisolated struct UITestNotificationAuthorizer: NotificationAuthorizing {
    func requestAuthorization() async throws -> Bool { false }
}
#endif
