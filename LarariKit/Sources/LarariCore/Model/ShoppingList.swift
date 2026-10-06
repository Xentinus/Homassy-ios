import CoreData
import Foundation

@objc(ShoppingList)
public final class ShoppingList: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var name: String
    @NSManaged public var color: String?
    @NSManaged public var sortOrder: Int32

    @NSManaged public var space: Space?
    @NSManaged public var items: NSSet?

    public var itemSet: Set<ShoppingListItem> { items as? Set<ShoppingListItem> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
