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

    /// True whenever the app was launched by a UI test.
    static var isActive: Bool { accountState != nil }

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
#endif
