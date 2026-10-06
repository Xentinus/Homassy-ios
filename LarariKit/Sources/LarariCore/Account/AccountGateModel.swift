import CloudKit
import Foundation
import Observation

/// Decides whether the app may be used: only an available iCloud account gets past the gate.
@MainActor
@Observable
public final class AccountGateModel {
    public private(set) var state: AccountState = .checking
    public private(set) var userRecordName: String?

    @ObservationIgnored private let provider: any AccountStatusProviding
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var observer: (any NSObjectProtocol)?
    @ObservationIgnored private var generation = 0

    /// Defaults key for the last known user record name (README "Offline record name").
    /// The app passes `AppModel.appDefaults`; LarariKit never names the App Group itself,
    /// because it cannot see the app's CLOUDKIT_ENABLED condition.
    public static let cachedUserRecordNameKey = "currentUserRecordName"

    public init(provider: any AccountStatusProviding, notificationCenter: NotificationCenter = .default,
                defaults: UserDefaults = .standard) {
        self.provider = provider
        self.notificationCenter = notificationCenter
        self.defaults = defaults
    }

    /// Errors that mean "offline or throttled", not "no account".
    public nonisolated static func isNetworkError(_ error: any Error) -> Bool {
        guard let code = (error as? CKError)?.code else { return false }
        return [.networkUnavailable, .networkFailure, .serviceUnavailable, .requestRateLimited].contains(code)
    }

    public nonisolated static func state(for status: CKAccountStatus) -> AccountState {
        switch status {
        case .available: .available
        case .noAccount: .noAccount
        case .restricted: .restricted
        case .temporarilyUnavailable: .temporarilyUnavailable
        case .couldNotDetermine: .couldNotDetermine
        @unknown default: .couldNotDetermine
        }
    }

    /// Re-reads the account. Shows `.checking` unless the account is currently available,
    /// so a background re-check never tears down the main UI.
    public func refresh() async {
        generation += 1
        let current = generation
        if state != .available { state = .checking }

        let (newState, recordName) = await resolve()
        guard current == generation else { return }
        state = newState
        userRecordName = recordName
    }

    private func resolve() async -> (AccountState, String?) {
        do {
            let status = try await provider.accountStatus()
            let mapped = Self.state(for: status)
            guard mapped == .available else { return (mapped, nil) }
            do {
                let recordName = try await provider.userRecordName()
                defaults.set(recordName, forKey: Self.cachedUserRecordNameKey)
                return (.available, recordName)
            } catch where Self.isNetworkError(error) {
                // Offline: fall back to the last known name so the app keeps working.
                guard let cached = defaults.string(forKey: Self.cachedUserRecordNameKey) else {
                    return (.couldNotDetermine, nil)
                }
                return (.available, cached)
            }
        } catch {
            return (.couldNotDetermine, nil)
        }
    }

    public func startObserving() {
        guard observer == nil else { return }
        observer = notificationCenter.addObserver(forName: .CKAccountChanged, object: nil, queue: nil) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.refresh() }
        }
    }

    public func stopObserving() {
        if let observer { notificationCenter.removeObserver(observer) }
        observer = nil
    }
}
