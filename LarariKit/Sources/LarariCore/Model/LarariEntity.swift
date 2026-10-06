import CoreData
import Foundation

/// Common columns of every Larari entity. `createdBy`/`updatedBy` hold CloudKit user record names.
public protocol LarariEntity: NSManagedObject {
    var publicId: UUID { get set }
    var createdAt: Date { get set }
    var updatedAt: Date { get set }
    var createdBy: String { get set }
    var updatedBy: String { get set }
}

extension LarariEntity {
    /// Records who changed the object and when. The first stamp also sets the creator.
    public func stamp(by userRecordName: String, now: Date = .now) {
        if createdBy.isEmpty {
            createdBy = userRecordName
            createdAt = now
        }
        updatedBy = userRecordName
        updatedAt = now
    }

    /// A typed fetch request. The entity name equals the class name for every Larari entity.
    public static func makeFetchRequest() -> NSFetchRequest<Self> {
        NSFetchRequest<Self>(entityName: String(describing: self))
    }

    /// Called from `awakeFromInsert`. It uses primitive setters, so inserting does not post extra change notifications.
    func prepareDefaults(now: Date = .now) {
        setPrimitiveValue(UUID(), forKey: "publicId")
        setPrimitiveValue(now, forKey: "createdAt")
        setPrimitiveValue(now, forKey: "updatedAt")
    }
}
