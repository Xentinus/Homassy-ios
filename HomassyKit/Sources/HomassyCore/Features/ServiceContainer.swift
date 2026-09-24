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
    public let notifications: ExpiryNotificationCoordinator

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true },
                notificationCenter: any NotificationCentering = SystemNotificationCenter()) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        products = ProductService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: canEdit)
        storageLocations = StorageLocationService(spaceStore: spaceStore, context: context,
                                                  userRecordName: userRecordName, canEdit: canEdit)
        inventory = InventoryService(spaceStore: spaceStore, context: context, userRecordName: userRecordName, canEdit: canEdit)
        notifications = ExpiryNotificationCoordinator(
            context: context, center: notificationCenter,
            locale: Locale(identifier: Bundle.main.preferredLocalizations.first ?? "en"))
    }

    /// The selected space, or Personal when nothing (or something that no longer exists) is selected.
    public func activeSpace(selectedID: UUID?) -> Space? {
        let spaces = (try? spaceStore.allSpaces()) ?? []
        if let selectedID, let match = spaces.first(where: { $0.publicId == selectedID }) { return match }
        return spaces.first
    }
}
