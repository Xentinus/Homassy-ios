import CoreData
import Foundation

@objc(ConsumptionLog)
public final class ConsumptionLog: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var consumedAt: Date?
    @NSManaged public var inventoryItem: InventoryItem?

    /// Amount consumed in this event.
    public var quantity: Decimal {
        get { decimal("quantity") ?? 0 }
        set { setDecimal(newValue, for: "quantity") }
    }

    /// Amount left on the item after this event.
    public var remaining: Decimal {
        get { decimal("remaining") ?? 0 }
        set { setDecimal(newValue, for: "remaining") }
    }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
