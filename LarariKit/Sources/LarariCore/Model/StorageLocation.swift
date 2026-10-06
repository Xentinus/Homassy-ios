import CoreData
import Foundation

@objc(StorageLocation)
public final class StorageLocation: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var name: String
    @NSManaged public var color: String?
    @NSManaged public var sortOrder: Int32
    @NSManaged public var isFreezer: Bool

    @NSManaged public var space: Space?
    @NSManaged public var inventoryItems: NSSet?

    public var inventoryItemSet: Set<InventoryItem> { inventoryItems as? Set<InventoryItem> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
