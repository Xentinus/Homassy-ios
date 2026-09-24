import CloudKit
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("LocalAccountStatusProvider")
struct LocalAccountStatusProviderTests {
    @Test func alwaysReportsAvailable() async throws {
        #expect(try await LocalAccountStatusProvider().accountStatus() == .available)
    }

    @Test func usesTheFixedLocalRecordName() async throws {
        #expect(LocalAccountStatusProvider.userRecordName == "_localDeveloper")
        #expect(try await LocalAccountStatusProvider().userRecordName() == "_localDeveloper")
    }

    @Test func gatePassesInLocalMode() async {
        let defaults = freshDefaults()
        let model = AccountGateModel(provider: LocalAccountStatusProvider(),
                                     notificationCenter: NotificationCenter(), defaults: defaults)
        await model.refresh()
        #expect(model.state == .available)
        #expect(model.userRecordName == "_localDeveloper")
        #expect(defaults.string(forKey: AccountGateModel.cachedUserRecordNameKey) == "_localDeveloper")
    }

    @Test func accountChangedNotificationKeepsTheGateOpen() async throws {
        let center = NotificationCenter()
        let model = AccountGateModel(provider: LocalAccountStatusProvider(), notificationCenter: center,
                                     defaults: freshDefaults())
        model.startObserving()
        await model.refresh()
        center.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(100))
        #expect(model.state == .available)
    }
}
