import CloudKit
import Foundation
import Testing
@testable import LarariCore

struct FakeAccountError: Error {}

actor FakeAccountStatusProvider: AccountStatusProviding {
    private var status: CKAccountStatus
    private var statusFails = false
    private var recordNameFails = false
    private var recordNameError: (any Error)?
    private(set) var statusCalls = 0

    init(status: CKAccountStatus) { self.status = status }

    func set(status: CKAccountStatus) { self.status = status }
    func failStatus() { statusFails = true }
    func failRecordName() { recordNameFails = true }
    func failRecordName(with error: any Error) { recordNameError = error }

    func accountStatus() async throws -> CKAccountStatus {
        statusCalls += 1
        if statusFails { throw FakeAccountError() }
        return status
    }

    func userRecordName() async throws -> String {
        if let recordNameError { throw recordNameError }
        if recordNameFails { throw FakeAccountError() }
        return "_abc123"
    }
}

/// A throwaway defaults suite, so tests never read or write the real record-name cache.
func freshDefaults() -> UserDefaults {
    let name = "AccountGateModelTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

@MainActor
@Suite("AccountGateModel")
struct AccountGateModelTests {
    @Test(arguments: zip(
        [CKAccountStatus.available, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine],
        [AccountState.available, .noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine]
    ))
    func mapsEveryAccountStatus(status: CKAccountStatus, expected: AccountState) {
        #expect(AccountGateModel.state(for: status) == expected)
    }

    @Test func startsInChecking() {
        let model = AccountGateModel(provider: FakeAccountStatusProvider(status: .available),
                                     notificationCenter: NotificationCenter(), defaults: freshDefaults())
        #expect(model.state == .checking)
        #expect(model.userRecordName == nil)
    }

    @Test(arguments: [CKAccountStatus.noAccount, .restricted, .temporarilyUnavailable, .couldNotDetermine])
    func refreshPublishesGateStates(status: CKAccountStatus) async {
        let model = AccountGateModel(provider: FakeAccountStatusProvider(status: status),
                                     notificationCenter: NotificationCenter(), defaults: freshDefaults())
        await model.refresh()
        #expect(model.state == AccountGateModel.state(for: status))
        #expect(model.userRecordName == nil)
    }

    @Test func availableStoresTheUserRecordName() async {
        let model = AccountGateModel(provider: FakeAccountStatusProvider(status: .available),
                                     notificationCenter: NotificationCenter(), defaults: freshDefaults())
        await model.refresh()
        #expect(model.state == .available)
        #expect(model.userRecordName == "_abc123")
    }

    @Test func statusErrorMeansCouldNotDetermine() async {
        let provider = FakeAccountStatusProvider(status: .available)
        await provider.failStatus()
        let model = AccountGateModel(provider: provider, notificationCenter: NotificationCenter(), defaults: freshDefaults())
        await model.refresh()
        #expect(model.state == .couldNotDetermine)
        #expect(model.userRecordName == nil)
    }

    @Test func recordNameErrorMeansCouldNotDetermine() async {
        let provider = FakeAccountStatusProvider(status: .available)
        await provider.failRecordName()
        let model = AccountGateModel(provider: provider, notificationCenter: NotificationCenter(), defaults: freshDefaults())
        await model.refresh()
        #expect(model.state == .couldNotDetermine)
        #expect(model.userRecordName == nil)
    }

    @Test func successfulFetchUpdatesTheCache() async {
        let defaults = freshDefaults()
        defaults.set("_old", forKey: AccountGateModel.cachedUserRecordNameKey)
        let model = AccountGateModel(provider: FakeAccountStatusProvider(status: .available),
                                     notificationCenter: NotificationCenter(), defaults: defaults)
        await model.refresh()
        #expect(defaults.string(forKey: AccountGateModel.cachedUserRecordNameKey) == "_abc123")
    }

    @Test(arguments: [CKError.Code.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited])
    func networkErrorUsesTheCachedRecordName(code: CKError.Code) async {
        let defaults = freshDefaults()
        defaults.set("_cached", forKey: AccountGateModel.cachedUserRecordNameKey)
        let provider = FakeAccountStatusProvider(status: .available)
        await provider.failRecordName(with: CKError(code))
        let model = AccountGateModel(provider: provider, notificationCenter: NotificationCenter(), defaults: defaults)
        await model.refresh()
        #expect(model.state == .available)
        #expect(model.userRecordName == "_cached")
    }

    @Test func networkErrorWithoutCacheMeansCouldNotDetermine() async {
        let provider = FakeAccountStatusProvider(status: .available)
        await provider.failRecordName(with: CKError(.networkUnavailable))
        let model = AccountGateModel(provider: provider, notificationCenter: NotificationCenter(), defaults: freshDefaults())
        await model.refresh()
        #expect(model.state == .couldNotDetermine)
        #expect(model.userRecordName == nil)
    }

    @Test func nonNetworkErrorIgnoresTheCache() async {
        let defaults = freshDefaults()
        defaults.set("_cached", forKey: AccountGateModel.cachedUserRecordNameKey)
        let provider = FakeAccountStatusProvider(status: .available)
        await provider.failRecordName(with: CKError(.notAuthenticated))
        let model = AccountGateModel(provider: provider, notificationCenter: NotificationCenter(), defaults: defaults)
        await model.refresh()
        #expect(model.state == .couldNotDetermine)
        #expect(model.userRecordName == nil)
    }

    @Test func accountChangedNotificationTriggersRefresh() async throws {
        let center = NotificationCenter()
        let provider = FakeAccountStatusProvider(status: .available)
        let model = AccountGateModel(provider: provider, notificationCenter: center, defaults: freshDefaults())
        model.startObserving()
        await model.refresh()
        #expect(model.state == .available)

        await provider.set(status: .noAccount)
        center.post(name: .CKAccountChanged, object: nil)

        try await waitUntil { model.state == .noAccount }
        #expect(model.userRecordName == nil)
    }

    @Test func startObservingIsIdempotent() async throws {
        let center = NotificationCenter()
        let provider = FakeAccountStatusProvider(status: .available)
        let model = AccountGateModel(provider: provider, notificationCenter: center, defaults: freshDefaults())
        model.startObserving()
        model.startObserving()
        await model.refresh()
        let before = await provider.statusCalls

        center.post(name: .CKAccountChanged, object: nil)
        try await waitUntil { await provider.statusCalls > before }
        try await Task.sleep(for: .milliseconds(100))

        #expect(await provider.statusCalls == before + 1)
    }

    @Test func stopObservingIgnoresLaterNotifications() async throws {
        let center = NotificationCenter()
        let provider = FakeAccountStatusProvider(status: .available)
        let model = AccountGateModel(provider: provider, notificationCenter: center, defaults: freshDefaults())
        model.startObserving()
        await model.refresh()
        model.stopObserving()

        await provider.set(status: .noAccount)
        center.post(name: .CKAccountChanged, object: nil)
        try await Task.sleep(for: .milliseconds(100))

        #expect(model.state == .available)
    }
}

/// Polls `condition` for up to two seconds.
@MainActor
func waitUntil(_ condition: @MainActor () async -> Bool) async throws {
    for _ in 0..<200 {
        if await condition() { return }
        try await Task.sleep(for: .milliseconds(10))
    }
    Issue.record("Condition not met within two seconds")
}
