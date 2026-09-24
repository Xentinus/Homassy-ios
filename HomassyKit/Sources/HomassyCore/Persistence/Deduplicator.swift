import CoreData
import Foundation

/// Merges objects that share a `publicId` within one persistent store.
///
/// The survivor is the object with the earliest `createdAt`; a tie goes to the smallest object ID URI.
/// Children on every to-many relationship of a duplicate are re-pointed to the survivor before the
/// duplicate is deleted. The context is not saved.
public enum Deduplicator {
    @MainActor
    public static func mergeDuplicates(entityName: String, in context: NSManagedObjectContext) throws -> Int {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.includesPendingChanges = true
        request.returnsObjectsAsFaults = false
        let objects = try context.fetch(request)

        let temporary = objects.filter { $0.objectID.isTemporaryID }
        if !temporary.isEmpty {
            try context.obtainPermanentIDs(for: temporary)
        }

        var groups: [GroupKey: [any HomassyEntity]] = [:]
        for object in objects {
            guard let entity = object as? any HomassyEntity else { continue }
            let key = GroupKey(storeIdentifier: object.objectID.persistentStore?.identifier ?? "",
                               publicId: entity.publicId)
            groups[key, default: []].append(entity)
        }

        var removed = 0
        for members in groups.values where members.count > 1 {
            let ordered = members.sorted(by: survives)
            let survivor = ordered[0]
            for duplicate in ordered.dropFirst() {
                repointChildren(of: duplicate, to: survivor)
                context.delete(duplicate)
                removed += 1
            }
        }
        return removed
    }

    private struct GroupKey: Hashable {
        let storeIdentifier: String
        let publicId: UUID
    }

    private static func survives(_ lhs: any HomassyEntity, _ rhs: any HomassyEntity) -> Bool {
        if lhs.createdAt != rhs.createdAt { return lhs.createdAt < rhs.createdAt }
        return lhs.objectID.uriRepresentation().absoluteString < rhs.objectID.uriRepresentation().absoluteString
    }

    private static func repointChildren(of duplicate: NSManagedObject, to survivor: NSManagedObject) {
        for (name, relationship) in duplicate.entity.relationshipsByName where relationship.isToMany {
            let children: [NSManagedObject]
            switch duplicate.value(forKey: name) {
            case let ordered as NSOrderedSet:
                children = ordered.array.compactMap { $0 as? NSManagedObject }
            case let set as NSSet:
                children = set.allObjects.compactMap { $0 as? NSManagedObject }
            default:
                children = []
            }
            guard !children.isEmpty else { continue }

            guard let inverse = relationship.inverseRelationship else {
                if relationship.isOrdered {
                    survivor.mutableOrderedSetValue(forKey: name).addObjects(from: children)
                } else {
                    survivor.mutableSetValue(forKey: name).addObjects(from: children)
                }
                continue
            }

            for child in children {
                if !inverse.isToMany {
                    child.setValue(survivor, forKey: inverse.name)
                } else if inverse.isOrdered {
                    let parents = child.mutableOrderedSetValue(forKey: inverse.name)
                    parents.remove(duplicate)
                    if !parents.contains(survivor) { parents.add(survivor) }
                } else {
                    let parents = child.mutableSetValue(forKey: inverse.name)
                    parents.remove(duplicate)
                    parents.add(survivor)
                }
            }
        }
    }
}
