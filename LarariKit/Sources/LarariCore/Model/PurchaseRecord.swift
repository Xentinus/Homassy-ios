import CoreData
import Foundation

/// One purchase of a product: where, how much and for how much (the amount paid). Written for every list
/// purchase and every stock added with a price or a store (P4-05); the product's price trend reads it.
/// Deleting the stock item or the store keeps the record; deleting the product removes it.
@objc(PurchaseRecord)
public final class PurchaseRecord: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var unitRaw: String
    @NSManaged public var currency: String?
    @NSManaged public var purchasedAt: Date?

    @NSManaged public var product: Product?
    @NSManaged public var shoppingLocation: ShoppingLocation?
    @NSManaged public var inventoryItem: InventoryItem?

    public var quantity: Decimal {
        get { decimal("quantity") ?? 0 }
        set { setDecimal(newValue, for: "quantity") }
    }

    /// The amount paid for `quantity`, not a unit price.
    public var price: Decimal? {
        get { decimal("price") }
        set { setDecimal(newValue, for: "price") }
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
