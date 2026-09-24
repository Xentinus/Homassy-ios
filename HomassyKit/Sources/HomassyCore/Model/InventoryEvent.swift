import CoreData
import Foundation

/// One entry in a product's stock history: added, consumed, moved, deleted or edited.
/// The actor is `createdBy`. Deleting the stock item keeps the event; deleting the product removes it.
@objc(InventoryEvent)
public final class InventoryEvent: NSManagedObject, HomassyEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var kindRaw: String
    @NSManaged public var unitRaw: String
    /// Storage location names at the time of the event, so the history survives renames and deletes.
    @NSManaged public var fromLocationName: String?
    @NSManaged public var toLocationName: String?
    @NSManaged public var occurredAt: Date?

    @NSManaged public var product: Product?
    @NSManaged public var inventoryItem: InventoryItem?

    public var kind: InventoryEventKind {
        get { InventoryEventKind(rawValue: kindRaw) ?? .edited }
        set { kindRaw = newValue.rawValue }
    }

    /// The amount the event is about: added, consumed, moved, or what was left when deleted.
    public var quantity: Decimal {
        get { decimal("quantity") ?? 0 }
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
