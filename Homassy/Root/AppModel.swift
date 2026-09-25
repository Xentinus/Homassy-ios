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
    /// The one cloud-sharing object; it also answers SpaceStore's share lookups.
    let cloudSharing: any CloudSharing
    /// iCloud sync status for the whole app lifetime (P5-05); fed by the container's event notifications.
    let syncStatus: SyncStatusModel
    /// Accepts share invitations; exists before the account check, since a cold-start invitation arrives early.
    let shareAcceptance: ShareAcceptanceModel
    let spaceStore: SpaceStore
    let accountGate: AccountGateModel
    let introduction: IntroductionModel
    let selection = SpaceSelection()
    let undoQueue = UndoQueue()
    private(set) var personalSpace: Space?
    /// Every domain service. Built once the account is available and the Personal space exists.
    private(set) var services: ServiceContainer?
    #if DEBUG
    /// `-uiTestAttribution`: a tracker with a simulated foreign change, used instead of the container's.
    private(set) var attributionOverride: AttributionTracker?
    #endif
    /// Runs persistent-history processing on every remote change (P5-04).
    private(set) var remoteChanges: RemoteChangeObserver?
    private var isBuildingServices = false
    private(set) var bootstrapError: (any Error)?

    init(persistence: PersistenceController,
         accountProvider: any AccountStatusProviding,
         defaults: UserDefaults = AppModel.appDefaults,
         introduction: IntroductionModel) {
        self.persistence = persistence
        cloudSharing = Self.makeCloudSharing(persistence: persistence)
        shareAcceptance = ShareAcceptanceModel(persistence: persistence, cloud: cloudSharing,
                                               containerIdentifier: Self.containerIdentifier)
        syncStatus = SyncStatusModel(privateStoreIdentifier: persistence.privateStore.identifier ?? "")
        spaceStore = SpaceStore(persistence: persistence, sharing: cloudSharing)
        accountGate = AccountGateModel(provider: accountProvider, defaults: defaults)
        self.introduction = introduction
        // Start consuming at once, before the stores finish their setup events.
        let events = SyncEventSource.events(from: persistence.container)
        Task { [syncStatus] in await syncStatus.consume(events) }
        syncStatus.onNotAuthenticated = { [weak self] in Task { await self?.accountGate.refresh() } }
        #if DEBUG
        if UITestHooks.simulatesSyncProblem {
            syncStatus.handle(SyncEventSnapshot(
                id: UUID(), storeIdentifier: persistence.privateStore.identifier ?? "", kind: .exporting,
                startDate: .now, endDate: .now, succeeded: false,
                failure: SyncFailureInfo(code: 25, isCloudKit: true)))      // CKError.quotaExceeded
        }
        #endif
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
        model.services = ServiceContainer(
            spaceStore: model.spaceStore, context: model.persistence.viewContext,
            userRecordName: UITestHooks.userRecordName, persistence: model.persistence,
            sharing: SharingService(persistence: model.persistence, spaceStore: model.spaceStore,
                                    cloud: model.cloudSharing, userRecordName: UITestHooks.userRecordName))
        return model
    }
    #endif

    /// ContainerCloudSharing only in CLOUDKIT_ENABLED builds outside UI tests; LocalCloudSharing otherwise.
    static func makeCloudSharing(persistence: PersistenceController) -> any CloudSharing {
        #if DEBUG
        if UITestHooks.isActive {
            let suite = "uiTest.localSharing"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return LocalCloudSharing(persistence: persistence, defaults: UserDefaults(suiteName: suite) ?? .standard)
        }
        #endif
        #if CLOUDKIT_ENABLED
        return ContainerCloudSharing(container: persistence.container)
        #else
        return LocalCloudSharing(persistence: persistence, defaults: appDefaults)
        #endif
    }

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
        let sharingService = SharingService(persistence: persistence, spaceStore: spaceStore,
                                            cloud: cloudSharing, userRecordName: userRecordName)
        let container = ServiceContainer(spaceStore: spaceStore, context: persistence.viewContext,
                                         userRecordName: userRecordName, notificationCenter: Self.notificationCenter,
                                         persistence: persistence, sharing: sharingService,
                                         historyDefaults: Self.appDefaults, syncStatus: syncStatus)
        #if DEBUG
        if UITestHooks.isSeeded {
            try? await UITestSeed.populate(container, in: personalSpace)
        }
        if UITestHooks.simulatesAttribution {
            let tracker = AttributionTracker(window: .seconds(120))
            let milk = try? container.products.products(in: personalSpace).first { $0.name == "Milk" }
            if let milk {
                tracker.record([ForeignChange(publicId: milk.publicId, entityName: "Product", userRecordName: "_uiTestFriend")])
            }
            attributionOverride = tracker
        }
        #endif
        services = container
        startRemoteChanges(for: container)
    }

    /// Merges and deduplicates imported history, flashes rows others changed, and refreshes the expiry
    /// schedule and badge when anything it depends on changed.
    private func startRemoteChanges(for container: ServiceContainer) {
        remoteChanges?.stop()
        guard let processor = container.history else { return }
        let attribution = container.attribution
        let notifications = container.notifications
        let observer = RemoteChangeObserver(container: persistence.container, processor: processor) { batch in
            attribution.record(batch.foreignChanges)
            let scheduleRelevant: Set<String> = ["Space", "Product", "InventoryItem", "StorageLocation"]
            if !batch.changedEntityNames.isDisjoint(with: scheduleRelevant) {
                notifications.scheduleRefresh(.remoteChange)    // also refreshes the badge
            }
        }
        observer.start()
        remoteChanges = observer
    }
}
