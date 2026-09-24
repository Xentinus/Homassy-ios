import CoreData
import Foundation

@objc(ShoppingLocation)
public final class ShoppingLocation: NSManagedObject, HomassyEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var mapItemIdentifier: String?
    @NSManaged public var name: String
    @NSManaged public var lastUsedAt: Date?

    @NSManaged public var space: Space?
    @NSManaged public var inventoryItems: NSSet?
    @NSManaged public var shoppingListItems: NSSet?

    public var latitude: Double? {
        get { primitive("latitude") }
        set { setPrimitive(newValue, for: "latitude") }
    }

    public var longitude: Double? {
        get { primitive("longitude") }
        set { setPrimitive(newValue, for: "longitude") }
    }

    public var inventoryItemSet: Set<InventoryItem> { inventoryItems as? Set<InventoryItem> ?? [] }
    public var shoppingListItemSet: Set<ShoppingListItem> { shoppingListItems as? Set<ShoppingListItem> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
