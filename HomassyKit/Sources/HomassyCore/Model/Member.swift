import CoreData
import Foundation

@objc(Member)
public final class Member: NSManagedObject, HomassyEntity {
    @NSManaged public var publicId: UUID
    @NSManaged public var createdAt: Date
    @NSManaged public var updatedAt: Date
    @NSManaged public var createdBy: String
    @NSManaged public var updatedBy: String

    @NSManaged public var userRecordName: String?
    @NSManaged public var displayName: String?
    @NSManaged public var colorSeed: String?
    @NSManaged public var avatar: Data?

    @NSManaged public var space: Space?

    public override func awakeFromInsert() {
        super.awakeFromInsert()
        prepareDefaults()
    }
}
