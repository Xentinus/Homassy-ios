import CoreData
import Foundation

@objc(Space)
public final class Space: NSManagedObject, LarariEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var name: String
    @NSManaged public var kindRaw: String
    @NSManaged public var sortOrder: Int32

    @NSManaged public var members: NSSet?
    @NSManaged public var products: NSSet?
    @NSManaged public var storageLocations: NSSet?
    @NSManaged public var shoppingLocations: NSSet?
    @NSManaged public var shoppingLists: NSSet?

    public var kind: SpaceKind {
        get { SpaceKind(rawValue: kindRaw) ?? .personal }
        set { kindRaw = newValue.rawValue }
    }

    public var memberSet: Set<Member> { members as? Set<Member> ?? [] }
    public var productSet: Set<Product> { products as? Set<Product> ?? [] }
    public var storageLocationSet: Set<StorageLocation> { storageLocations as? Set<StorageLocation> ?? [] }
    public var shoppingLocationSet: Set<ShoppingLocation> { shoppingLocations as? Set<ShoppingLocation> ?? [] }
    public var shoppingListSet: Set<ShoppingList> { shoppingLists as? Set<ShoppingList> ?? [] }

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
