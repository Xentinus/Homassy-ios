import CoreData
import Foundation
import HomassyCore
import Observation

/// The single composition root. `AppModel.shared` is the only instance outside previews:
/// `HomassyApp` injects it.
/// Later tasks add stored properties here: `selection` (P1-07), `undoQueue` (P1-08), `services` (P2-05).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    static let containerIdentifier = "iCloud.com.homassy.app"
    static let appGroup = "group.com.homassy.app"

    /// True only in builds with the CLOUDKIT_ENABLED compilation condition (C-01).
    static var isCloudKitEnabled: Bool {
        #if CLOUDKIT_ENABLED
        true
        #else
        false
        #endif
    }

    /// The one defaults store for app-wide caches (record name, history tokens).
    /// Local mode has no App Group, so it uses the standard defaults.
    static var appDefaults: UserDefaults {
        #if CLOUDKIT_ENABLED
        UserDefaults(suiteName: appGroup) ?? .standard
        #else
        .standard
        #endif
    }

    /// Store and account source for a normal (non-UI-test) launch.
    /// Local mode: SQLite in Application Support + an always-available local account.
    /// Cloud mode (C-01): CloudKit stores in the App Group + the real iCloud account.
    static func releaseConfiguration() -> (mode: StoreMode, provider: any AccountStatusProviding) {
        #if CLOUDKIT_ENABLED
        (.cloudKit(containerIdentifier: containerIdentifier, appGroup: appGroup),
         CloudKitAccountStatus(containerIdentifier: containerIdentifier))
        #else
        (StoreMode.localDevelopment, LocalAccountStatusProvider())
        #endif
    }

    let persistence: PersistenceController
    let spaceStore: SpaceStore
    let accountGate: AccountGateModel
    private(set) var personalSpace: Space?
    private(set) var bootstrapError: (any Error)?

    init(persistence: PersistenceController, accountProvider: any AccountStatusProviding,
         defaults: UserDefaults = AppModel.appDefaults) {
        self.persistence = persistence
        spaceStore = SpaceStore(persistence: persistence, sharing: ContainerShareLookup(container: persistence.container))
        accountGate = AccountGateModel(provider: accountProvider, defaults: defaults)
    }

    /// The app's real configuration, or the UI-test configuration when launched by HomassyUITests.
    convenience init() {
        let release = Self.releaseConfiguration()
        let configuration: (mode: StoreMode, provider: any AccountStatusProviding, defaults: UserDefaults)
        #if DEBUG
        if let testState = UITestHooks.accountState {
            // never touch the real store or cache
            configuration = (.inMemory, UITestAccountStatus(state: testState),
                             UserDefaults(suiteName: "uiTest.accountGate") ?? .standard)
        } else {
            configuration = (release.mode, release.provider, Self.appDefaults)
        }
        #else
        configuration = (release.mode, release.provider, Self.appDefaults)
        #endif
        let (mode, provider, defaults) = configuration

        let persistence: PersistenceController
        do {
            persistence = try PersistenceController(mode: mode)
        } catch {
            fatalError("Homassy could not open its stores: \(error)")
        }
        self.init(persistence: persistence, accountProvider: provider, defaults: defaults)
    }

    #if DEBUG
    /// For SwiftUI previews: seeded in-memory store, available account, Personal space bootstrapped.
    static func preview() -> AppModel {
        let model = AppModel(persistence: .preview(), accountProvider: UITestAccountStatus(state: .available),
                             defaults: UserDefaults(suiteName: "preview.accountGate") ?? .standard)
        model.personalSpace = try? model.spaceStore.bootstrapPersonalSpace(userRecordName: UITestHooks.userRecordName)
        return model
    }
    #endif

    /// Creates or finds the Personal space once the account is known. Safe to call repeatedly.
    func bootstrapPersonalSpace() {
        guard let userRecordName = accountGate.userRecordName else { return }
        do {
            personalSpace = try spaceStore.bootstrapPersonalSpace(userRecordName: userRecordName)
            bootstrapError = nil
        } catch {
            bootstrapError = error
        }
    }
}
