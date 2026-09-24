import CoreData
import Foundation

@objc(InventoryItem)
public final class InventoryItem: NSManagedObject, HomassyEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var unitRaw: String
    @NSManaged public var expiresAt: Date?
    @NSManaged public var purchasedAt: Date?
    @NSManaged public var currency: String?
    @NSManaged public var isFullyConsumed: Bool
    @NSManaged public var consumedAt: Date?

    @NSManaged public var product: Product?
    @NSManaged public var storageLocation: StorageLocation?
    @NSManaged public var shoppingLocation: ShoppingLocation?
    @NSManaged public var consumptionLogs: NSSet?

    /// Stored as Core Data Decimal. You cannot sort by it with a Swift key path; use `NSSortDescriptor(key: "quantity", …)`.
    public var quantity: Decimal {
        get { decimal("quantity") ?? 0 }
        set { setDecimal(newValue, for: "quantity") }
    }

    public var price: Decimal? {
        get { decimal("price") }
        set { setDecimal(newValue, for: "price") }
    }

    public var unit: MeasureUnit {
        get { MeasureUnit(rawValue: unitRaw) ?? .piece }
        set { unitRaw = newValue.rawValue }
    }

    public var consumptionLogSet: Set<ConsumptionLog> { consumptionLogs as? Set<ConsumptionLog> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
