import CoreData
import Foundation
import LarariCore
import LarariShared
import Observation

/// The single composition root. `AppModel.shared` is the only instance outside previews:
/// `LarariApp` injects it.
/// Later tasks add stored properties here: `undoQueues` (N-03; P1-08's single queue before), `services` (P2-05).
/// The selected space and the undo queue are per window since N-03 (`SceneRoot`).
@MainActor
@Observable
final class AppModel {
    static let shared = AppModel()

    static let containerIdentifier = "iCloud.app.larari"
    static let appGroup = "group.app.larari"

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
    /// Location for the store reminders (P4-06); nil under UI tests, so they never read the position.
    private let storeLocation: CoreLocationAuthorizer?
    /// iCloud sync status for the whole app lifetime (P5-05); fed by the container's event notifications.
    let syncStatus: SyncStatusModel
    /// Accepts share invitations; exists before the account check, since a cold-start invitation arrives early.
    let shareAcceptance: ShareAcceptanceModel
    let spaceStore: SpaceStore
    let accountGate: AccountGateModel
    let introduction: IntroductionModel
    /// One undo queue per window (N-03, Apple's per-window undo). The registry commits them all at once.
    let undoQueues = UndoQueueRegistry()
    /// The space whose first-visit member setup is on screen in some window, so only one window asks (N-03).
    var memberSetupSpaceID: UUID?
    #if DEBUG
    /// Previews only: the state one window would have. Real windows get theirs from `SceneRoot`.
    let selection = SpaceSelection()
    let undoQueue = UndoQueue()
    #endif
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
    private var shareRefresh: Task<Void, Never>?
    private(set) var bootstrapError: (any Error)?

    init(persistence: PersistenceController,
         accountProvider: any AccountStatusProviding,
         defaults: UserDefaults = AppModel.appDefaults,
         introduction: IntroductionModel) {
        self.persistence = persistence
        StoreReminderSettings.registerDefault()
        #if DEBUG
        storeLocation = UITestHooks.isActive ? nil : CoreLocationAuthorizer()
        #else
        storeLocation = CoreLocationAuthorizer()
        #endif
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

    /// The app's real configuration, or the UI-test configuration when launched by LarariUITests.
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

        #if CLOUDKIT_ENABLED
        if case .cloudKit = mode {
            Self.migrateLocalStoreIfNeeded(mode: mode)
        }
        #endif
        let persistence: PersistenceController
        do {
            persistence = try PersistenceController(mode: mode)
        } catch {
            fatalError("Larari could not open its stores: \(error)")
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

    #if CLOUDKIT_ENABLED
    /// First cloud launch after the local phase: move the local SQLite store into the App Group store
    /// before NSPersistentCloudKitContainer loads it (C-01). A failure is logged and leaves the local
    /// store in place; the P3 archive path is the fallback.
    private static func migrateLocalStoreIfNeeded(mode: StoreMode) {
        do {
            let destination = try PersistenceController.storeDirectory(for: mode)
            let result = try LocalStoreMigrator.migrate(from: StoreMode.localDevelopmentDirectory, to: destination)
            if case .migrated = result {
                appDefaults.set(true, forKey: LocalStoreMigrator.pendingAdoptionKey)
                UserDefaults.standard.removeObject(forKey: LocalCloudSharing.sharedSpaceIDsKey)
            }
        } catch {
            print("Larari: local store migration failed: \(error)")
        }
    }
    #endif

    #if DEBUG
    /// For SwiftUI previews: seeded in-memory store, available account, Personal space bootstrapped.
    static func preview() -> AppModel {
        let seen = UserDefaults(suiteName: "LarariPreview")!
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
        return ContainerCloudSharing(persistence: persistence, backend: ContainerSharingBackend(persistence: persistence))
        #else
        return LocalCloudSharing(persistence: persistence, defaults: appDefaults)
        #endif
    }

    /// Creates or finds the Personal space once the account is known. Safe to call repeatedly.
    func bootstrapPersonalSpace() {
        guard let userRecordName = accountGate.userRecordName else { return }
        do {
            #if CLOUDKIT_ENABLED
            if Self.appDefaults.bool(forKey: LocalStoreMigrator.pendingAdoptionKey) {
                try LocalStoreMigrator.adoptLocalData(in: persistence, to: userRecordName)
                Self.appDefaults.removeObject(forKey: LocalStoreMigrator.pendingAdoptionKey)
            }
            #endif
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
        if NotificationPreviewCenter.isRequested { return NotificationPreviewCenter() }
        #endif
        return SystemNotificationCenter()
    }

    /// ActivityKit on a normal launch; an in-memory recorder under UI tests (N-04).
    static var liveActivityController: any LiveActivityControlling {
        #if DEBUG
        if UITestHooks.isActive { return UITestLiveActivityController.shared }
        #endif
        return ActivityKitShoppingController()
    }

    /// The Live Activity memory (N-04): the app defaults, or under UI tests a suite wiped on every launch, so runs
    /// never suppress each other or touch the real app's record.
    static var shoppingActivityDefaults: UserDefaults {
        #if DEBUG
        if UITestHooks.isActive {
            let suite = "uiTest.shoppingActivity"
            UserDefaults.standard.removePersistentDomain(forName: suite)
            return UserDefaults(suiteName: suite) ?? .standard
        }
        #endif
        return appDefaults
    }

    /// Builds the one `ServiceContainer` (and applies the UI-test seed) after the Personal space is bootstrapped.
    func buildServices() async {
        guard services == nil, !isBuildingServices,
              let personalSpace, let userRecordName = accountGate.userRecordName else { return }
        isBuildingServices = true
        defer { isBuildingServices = false }
        let sharingService = SharingService(persistence: persistence, spaceStore: spaceStore,
                                            cloud: cloudSharing, userRecordName: userRecordName)
        #if DEBUG
        let storeAddressCacheURL = UITestHooks.isActive ? nil : StoreAddressCache.defaultURL
        let storeAddresses: (any StoreAddressResolving)? = UITestHooks.isActive ? nil : MapKitStoreAddressResolver()
        #else
        let storeAddressCacheURL = StoreAddressCache.defaultURL
        let storeAddresses: (any StoreAddressResolving)? = MapKitStoreAddressResolver()
        #endif
        let container = ServiceContainer(spaceStore: spaceStore, context: persistence.viewContext,
                                         userRecordName: userRecordName, notificationCenter: Self.notificationCenter,
                                         persistence: persistence, sharing: sharingService,
                                         historyDefaults: Self.appDefaults, syncStatus: syncStatus,
                                         locationAuthorizer: storeLocation,
                                         storeRemindersEnabled: { StoreReminderSettings.isEnabled },
                                         storeAddressCacheURL: storeAddressCacheURL,
                                         storeAddresses: storeAddresses,
                                         liveActivities: Self.liveActivityController,
                                         shoppingActivityDefaults: Self.shoppingActivityDefaults)
        #if DEBUG
        if UITestHooks.isSeeded {
            try? await UITestSeed.populate(container, in: personalSpace)
            if UITestHooks.seedsStoreItems { try? UITestSeed.populateStoreItems(container, in: personalSpace) }
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
        scheduleShareRefresh(after: .zero)
        storeLocation?.onAccessChange = { container.storeReminders.scheduleRefresh(.authorization) }
        startRemoteChanges(for: container)
        container.shoppingActivity.scheduleRefresh()     // adopts an activity that outlived the previous process, or ends it when its store is gone
    }

    /// Re-reads shares and permissions off the main thread (P5-06): at launch, after remote changes (debounced, an
    /// import posts many) and when the app becomes active, so removals and permission changes show once imported.
    func scheduleShareRefresh(after delay: Duration = .seconds(1)) {
        shareRefresh?.cancel()
        shareRefresh = Task { [cloudSharing] in
            if delay > .zero {
                do { try await Task.sleep(for: delay) } catch { return }
            }
            await cloudSharing.refreshShares()
        }
    }

    /// The services for work without a scene (N-01 background refresh): a background launch never shows RootView,
    /// so the account check, the Personal space bootstrap and the service build run here. Safe to call while
    /// RootView builds them too; returns nil when the account is not available or the task was cancelled.
    func prepareServices() async -> ServiceContainer? {
        if let services { return services }
        if accountGate.state != .available { await accountGate.refresh() }
        guard accountGate.state == .available, let userRecordName = accountGate.userRecordName else { return nil }
        if personalSpace == nil {
            do {
                personalSpace = try spaceStore.bootstrapPersonalSpace(userRecordName: userRecordName)
                bootstrapError = nil
            } catch {
                bootstrapError = error
                return nil
            }
        }
        await buildServices()
        while services == nil, isBuildingServices {            // RootView's build is still running
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return nil }
        }
        return services
    }

    /// Merges and deduplicates imported history, flashes rows others changed, and refreshes the expiry
    /// schedule and badge when anything it depends on changed.
    private func startRemoteChanges(for container: ServiceContainer) {
        remoteChanges?.stop()
        guard let processor = container.history else { return }
        let attribution = container.attribution
        let notifications = container.notifications
        let storeReminders = container.storeReminders
        let shoppingActivity = container.shoppingActivity
        let observer = RemoteChangeObserver(container: persistence.container, processor: processor) { batch in
            attribution.record(batch.foreignChanges)
            let scheduleRelevant: Set<String> = ["Space", "Product", "InventoryItem", "StorageLocation"]
            if !batch.changedEntityNames.isDisjoint(with: scheduleRelevant) {
                notifications.scheduleRefresh(.remoteChange)    // also refreshes the badge
            }
            if !batch.changedEntityNames.isDisjoint(with: ["ShoppingListItem", "ShoppingLocation", "ShoppingList"]) {
                storeReminders.scheduleRefresh(.remoteChange)
            }
            if !batch.changedEntityNames.isDisjoint(with: ["ShoppingListItem", "ShoppingList", "ShoppingLocation", "Product", "Space"]) {
                shoppingActivity.scheduleRefresh()
            }
        }
        observer.start()
        remoteChanges = observer
    }

    /// On launch, every foreground and after an arrival notification tap (N-04 D9 B): where the user is, which chain
    /// branches the store reminders know, and the window's household decide whether the shopping Live Activity starts.
    func evaluateShoppingActivity(preferredSpaceID: UUID?) async {
        guard let services else { return }
        var branches = services.storeReminders.lastPlan.compactMap { reminder in
            StoreReminderPlanner.chainKey(fromIdentifier: reminder.identifier).map {
                ChainBranch(chainKey: $0, center: reminder.center)
            }
        }
        if let arrival = AppRouter.shared.arrivalBranch { branches.append(arrival) }
        await services.shoppingActivity.evaluate(position: await shoppingPosition(), branches: branches,
                                                 preferredSpaceID: preferredSpaceID)
    }

    private func shoppingPosition() async -> Coordinate? {
        #if DEBUG
        if let position = UITestHooks.nearStorePosition { return position }
        #endif
        return await storeLocation?.currentCoordinate()
    }

    /// `TickShoppingItemIntent` through `ShoppingTickBridge` (registered in AppDelegate), also in a background launch.
    func tick(itemIDs: [UUID]) async {
        guard let services = await prepareServices() else { return }
        await services.shoppingActivity.tick(itemIDs: itemIDs)
    }
}
