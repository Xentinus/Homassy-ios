import CoreData
import Foundation

@objc(Product)
public final class Product: NSManagedObject, HomassyEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var name: String
    @NSManaged public var brand: String?
    @NSManaged public var category: String?
    @NSManaged public var barcode: String?
    @NSManaged public var defaultUnitRaw: String
    @NSManaged public var isEatable: Bool
    @NSManaged public var isFavorite: Bool
    @NSManaged public var notes: String?
    @NSManaged public var image: Data?

    @NSManaged public var space: Space?
    @NSManaged public var inventoryItems: NSSet?
    @NSManaged public var shoppingListItems: NSSet?

    public var defaultUnit: MeasureUnit {
        get { MeasureUnit(rawValue: defaultUnitRaw) ?? .piece }
        set { defaultUnitRaw = newValue.rawValue }
    }

    public var inventoryItemSet: Set<InventoryItem> { inventoryItems as? Set<InventoryItem> ?? [] }
    public var shoppingListItemSet: Set<ShoppingListItem> { shoppingListItems as? Set<ShoppingListItem> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
