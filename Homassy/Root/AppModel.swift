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
    let introduction: IntroductionModel
    let selection = SpaceSelection()
    let undoQueue = UndoQueue()
    private(set) var personalSpace: Space?
    /// Every domain service. Built once the account is available and the Personal space exists.
    private(set) var services: ServiceContainer?
    private var isBuildingServices = false
    private(set) var bootstrapError: (any Error)?

    init(persistence: PersistenceController,
         accountProvider: any AccountStatusProviding,
         defaults: UserDefaults = AppModel.appDefaults,
         introduction: IntroductionModel) {
        self.persistence = persistence
        spaceStore = SpaceStore(persistence: persistence, sharing: ContainerShareLookup(container: persistence.container))
        accountGate = AccountGateModel(provider: accountProvider, defaults: defaults)
        self.introduction = introduction
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
        let notifications: any NotificationAuthorizing
        #if DEBUG
        if UITestHooks.resetIntroduction {
            UserDefaults.standard.removeObject(forKey: IntroductionModel.defaultsKey)
        }
        notifications = UITestHooks.isActive ? UITestNotificationAuthorizer() : UserNotificationAuthorizer()
        #else
        notifications = UserNotificationAuthorizer()
        #endif
        self.init(persistence: persistence,
                  accountProvider: provider,
                  defaults: defaults,
                  introduction: IntroductionModel(notifications: notifications))
    }

    #if DEBUG
    /// For SwiftUI previews: seeded in-memory store, available account, Personal space bootstrapped.
    static func preview() -> AppModel {
        let seen = UserDefaults(suiteName: "HomassyPreview")!
        seen.set(true, forKey: IntroductionModel.defaultsKey)
        let model = AppModel(persistence: .preview(),
                             accountProvider: UITestAccountStatus(state: .available),
                             defaults: seen,
                             introduction: IntroductionModel(defaults: seen, notifications: UITestNotificationAuthorizer()))
        model.personalSpace = try? model.spaceStore.bootstrapPersonalSpace(userRecordName: UITestHooks.userRecordName)
        model.services = ServiceContainer(spaceStore: model.spaceStore, context: model.persistence.viewContext,
                                          userRecordName: UITestHooks.userRecordName, persistence: model.persistence)
        return model
    }
    #endif

    /// Creates or finds the Personal space once the account is known. Safe to call repeatedly.
    func bootstrapPersonalSpace() {
        guard let userRecordName = accountGate.userRecordName else { return }
        do {
            personalSpace = try spaceStore.bootstrapPersonalSpace(userRecordName: userRecordName)
            bootstrapError = nil
            Task { await buildServices() }
        } catch {
            bootstrapError = error
        }
    }

    /// The real notification center, or under UI tests one that schedules nothing and never touches the badge,
    /// so seeded test data leaves no notifications behind on the test iPhone.
    static var notificationCenter: any NotificationCentering {
        #if DEBUG
        if UITestHooks.isActive { return UITestNotificationCenter() }
        #endif
        return SystemNotificationCenter()
    }

    /// Builds the one `ServiceContainer` (and applies the UI-test seed) after the Personal space is bootstrapped.
    func buildServices() async {
        guard services == nil, !isBuildingServices,
              let personalSpace, let userRecordName = accountGate.userRecordName else { return }
        isBuildingServices = true
        defer { isBuildingServices = false }
        let container = ServiceContainer(spaceStore: spaceStore, context: persistence.viewContext,
                                         userRecordName: userRecordName, notificationCenter: Self.notificationCenter,
                                         persistence: persistence)
        #if DEBUG
        if UITestHooks.isSeeded {
            try? await UITestSeed.populate(container, in: personalSpace)
        }
        #endif
        services = container
    }
}
