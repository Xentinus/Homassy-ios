import CoreData
import Foundation

@objc(ShoppingListItem)
public final class ShoppingListItem: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var customName: String?
    @NSManaged public var unitRaw: String
    @NSManaged public var note: String?
    @NSManaged public var deadline: Date?
    @NSManaged public var isPurchased: Bool
    @NSManaged public var purchasedAt: Date?
    @NSManaged public var sortOrder: Int32

    @NSManaged public var shoppingList: ShoppingList?
    @NSManaged public var product: Product?
    @NSManaged public var shoppingLocation: ShoppingLocation?

    public var quantity: Decimal {
        get { decimal("quantity") ?? 1 }
        set { setDecimal(newValue, for: "quantity") }
    }

    public var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
