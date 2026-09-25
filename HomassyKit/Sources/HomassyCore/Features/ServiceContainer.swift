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
    public let pendingDeletions = PendingDeletions()
    public let products: ProductService
    public let storageLocations: StorageLocationService
    public let inventory: InventoryService
    public let shopping: ShoppingService
    public let shoppingLocations: ShoppingLocationService
    /// Apple Maps store search; a fake in tests.
    public let storeSearch: any StoreSearching
    public let notifications: ExpiryNotificationCoordinator
    /// Export and import. Nil only in package tests that build the container without persistence.
    public let archive: ArchiveServices?

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                notificationCenter: any NotificationCentering = SystemNotificationCenter(),
                persistence: PersistenceController? = nil,
                storeSearch: any StoreSearching = MapKitStoreSearch()) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        products = ProductService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: canEdit)
        storageLocations = StorageLocationService(spaceStore: spaceStore, context: context,
                                                  userRecordName: userRecordName, canEdit: canEdit)
        inventory = InventoryService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: canEdit)
        shopping = ShoppingService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: canEdit)
        shoppingLocations = ShoppingLocationService(spaceStore: spaceStore, context: context,
                                                    userRecordName: userRecordName, canEdit: canEdit)
        self.storeSearch = storeSearch
        notifications = ExpiryNotificationCoordinator(
            context: context, center: notificationCenter,
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
        archive = persistence.map { ArchiveServices(persistence: $0, spaceStore: spaceStore, userRecordName: userRecordName) }
    }

    /// The selected space, or Personal when nothing (or something that no longer exists) is selected.
    public func activeSpace(selectedID: UUID?) -> Space? {
        let spaces = (try? spaceStore.allSpaces()) ?? []
        if let selectedID, let match = spaces.first(where: { $0.publicId == selectedID }) { return match }
        return spaces.first
    }
}
