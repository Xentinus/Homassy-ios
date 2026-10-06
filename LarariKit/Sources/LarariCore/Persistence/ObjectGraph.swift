import CoreData

/// Walks every relationship from a root. Spaces never relate across each other (§3.3), so from a
/// Space this is exactly the graph NSPersistentCloudKitContainer places in the space's zone.
public enum ObjectGraph {
    @MainActor
    public static func objectIDs(reachableFrom root: NSManagedObject) -> Set<NSManagedObjectID> {
        var visited: Set<NSManagedObjectID> = []
        var pending: [NSManagedObject] = [root]
        while let object = pending.popLast() {
            guard visited.insert(object.objectID).inserted else { continue }
            for name in object.entity.relationshipsByName.keys {
                switch object.value(forKey: name) {
                case let related as NSManagedObject:
                    pending.append(related)
                case let set as NSSet:
                    pending.append(contentsOf: set.compactMap { $0 as? NSManagedObject })
                case let ordered as NSOrderedSet:
                    pending.append(contentsOf: ordered.compactMap { $0 as? NSManagedObject })
                default:
                    break
                }
            }
        }
        return visited
    }
}
