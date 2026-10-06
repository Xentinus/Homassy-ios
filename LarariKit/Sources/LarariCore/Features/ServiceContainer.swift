import CoreData
import Foundation
import Observation

/// Every domain service, built once by `AppModel` after the account gate and put in the SwiftUI environment
/// by `RootView`. Later tasks add stored properties here (inventory, notifications, archive, shopping, …).
@MainActor
@Observable
public final class ServiceContainer {
    public let spaceStore: SpaceStore
    public let context: NSManagedObjectContext
    public let userRecordName: String
    public let pendingDeletions: PendingDeletions
    public let products: ProductService
    public let storageLocations: StorageLocationService
    public let inventory: InventoryService
    public let shopping: ShoppingService
    public let shoppingLocations: ShoppingLocationService
    /// Store addresses cached on this device (P2-08b).
    public let storeAddressCache: StoreAddressCache
    /// Which store is which: cached addresses, distance, compact names (P2-08b).
    public let storeDirectory: StoreDirectory
    /// Apple Maps store search; a fake in tests.
    public let storeSearch: any StoreSearching
    public let notifications: ExpiryNotificationCoordinator
    /// Store arrival reminders (P4-06); idle unless the app passes a location authorizer and the switch is on.
    public let storeReminders: StoreReminderCoordinator
    /// The shopping Live Activity (N-04); switched off (`NoLiveActivities`) unless the app passes ActivityKit.
    public let shoppingActivity: ShoppingActivityCoordinator
    /// Export and import. Nil only in package tests that build the container without persistence.
    public let archive: ArchiveServices?
    /// Households: create, share, leave, delete. Nil only in package tests that build the container without it.
    public let sharing: SharingService?
    /// Member records: names, photos, colours. Built from `sharing` when the container has one.
    public let members: MemberService?
    /// Persistent history of remote changes (P5-04): merge, dedupe, attribution. Built from `sharing`.
    public let history: HistoryProcessor?
    /// Rows recently changed by someone else, for the attribution flash.
    public let attribution = AttributionTracker()
    /// iCloud sync status: AppModel's app-lifetime instance (P5-05); a fresh idle one in package tests.
    public let syncStatus: SyncStatusModel

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                notificationCenter: any NotificationCentering = SystemNotificationCenter(),
                persistence: PersistenceController? = nil,
                storeSearch: any StoreSearching = MapKitStoreSearch(),
                sharing: SharingService? = nil,
                historyDefaults: UserDefaults = .standard,
                syncStatus: SyncStatusModel? = nil,
                locationAuthorizer: (any LocationAuthorizing)? = nil,
                storeRemindersEnabled: @escaping @MainActor () -> Bool = { false },
                storeAddressCacheURL: URL? = nil,
                storeAddresses: (any StoreAddressResolving)? = nil,
                liveActivities: (any LiveActivityControlling)? = nil,
                shoppingActivityDefaults: UserDefaults = .standard) {
        let pending = PendingDeletions()
        pendingDeletions = pending
        // When sharing is given, its permission check is every service's canEdit (read-only households).
        let permission: @MainActor (Space) -> Bool
        if let sharing {
            permission = { sharing.canEdit($0) }
        } else {
            permission = canEdit
        }
        self.sharing = sharing
        self.syncStatus = syncStatus ?? SyncStatusModel(privateStoreIdentifier: "")
        members = sharing.map { MemberService(persistence: $0.persistence, spaceStore: spaceStore,
                                              sharing: $0, userRecordName: userRecordName) }
        history = sharing.map { sharing in
            HistoryProcessor(container: sharing.persistence.container,
                             tokens: HistoryTokenStore(defaults: historyDefaults),
                             currentUserRecordName: userRecordName,
                             deduplicateStore: sharing.persistence.privateStore)
        }
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        products = ProductService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: permission)
        storageLocations = StorageLocationService(spaceStore: spaceStore, context: context,
                                                  userRecordName: userRecordName, canEdit: permission)
        let inventoryService = InventoryService(spaceStore: spaceStore, context: context, userRecordName: userRecordName,
                                                canEdit: permission)
        inventory = inventoryService
        let shoppingService = ShoppingService(spaceStore: spaceStore, context: context, userRecordName: userRecordName,
                                              canEdit: permission)
        shopping = shoppingService
        shoppingLocations = ShoppingLocationService(spaceStore: spaceStore, context: context,
                                                    userRecordName: userRecordName, canEdit: permission)
        storeAddressCache = StoreAddressCache(fileURL: storeAddressCacheURL)
        storeDirectory = StoreDirectory(context: context, cache: storeAddressCache, resolver: storeAddresses,
                                        location: locationAuthorizer)
        self.storeSearch = storeSearch
        notifications = ExpiryNotificationCoordinator(
            context: context, center: notificationCenter,
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        storeReminders = StoreReminderCoordinator(
            context: context, center: notificationCenter, search: storeSearch, location: locationAuthorizer,
            isEnabled: storeRemindersEnabled,
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        shoppingActivity = ShoppingActivityCoordinator(
            shopping: shoppingService, inventory: inventoryService, pending: pending,
            controller: liveActivities ?? NoLiveActivities(),
            memory: ShoppingActivityMemory(defaults: shoppingActivityDefaults),
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        archive = persistence.map { ArchiveServices(persistence: $0, spaceStore: spaceStore, userRecordName: userRecordName,
                                                          canEdit: permission) }
        shoppingLocations.onUpsert = { [storeDirectory] in storeDirectory.remember($0) }
    }

    /// The selected space, or Personal when nothing (or something that no longer exists) is selected.
    public func activeSpace(selectedID: UUID?) -> Space? {
        let spaces = (try? spaceStore.allSpaces()) ?? []
        if let selectedID, let match = spaces.first(where: { $0.publicId == selectedID }) { return match }
        return spaces.first
    }

    /// What a background app refresh recomputes (N-01), in order: the expiry summaries and the badge, then the
    /// store arrival reminders. The session checks for expiration between the steps.
    public var backgroundRefreshSteps: [@MainActor () async -> Void] {
        let notifications = notifications
        let storeReminders = storeReminders
        return [
            { await notifications.refresh() },
            { await storeReminders.refreshInBackground() },
        ]
    }
}
