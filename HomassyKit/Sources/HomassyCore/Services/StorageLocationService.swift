import CoreData
import Foundation

@MainActor
public final class StorageLocationService {
    private let spaceStore: SpaceStore
    private let context: NSManagedObjectContext
    private let userRecordName: String
    private let canEditSpace: @MainActor (Space) -> Bool

    public init(spaceStore: SpaceStore, context: NSManagedObjectContext, userRecordName: String,
                canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) {
        self.spaceStore = spaceStore
        self.context = context
        self.userRecordName = userRecordName
        self.canEditSpace = canEdit
    }

    public func canEdit(_ space: Space) -> Bool { canEditSpace(space) }

    // MARK: Reading

    public func locations(in space: Space) throws -> [StorageLocation] {
        try context.fetchEntities(StorageLocation.self, where: NSPredicate(format: "space == %@", space))
            .sorted {
                let (left, right) = (Int($0.sortOrder), Int($1.sortOrder))
                if left != right { return left < right }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }
    }

    public func location(publicId: UUID) throws -> StorageLocation? {
        try context.fetchEntities(StorageLocation.self, where: NSPredicate(format: "publicId == %@", publicId as CVarArg)).first
    }

    public func location(named name: String, in space: Space) throws -> StorageLocation? {
        guard let value = name.nilIfBlank else { return nil }
        return try locations(in: space).first { $0.name.caseInsensitiveCompare(value) == .orderedSame }
    }

    public func itemCount(in location: StorageLocation) throws -> Int {
        try context.countEntities(InventoryItem.self,
                                  where: NSPredicate(format: "storageLocation == %@ AND isFullyConsumed == NO", location))
    }

    // MARK: Writing

    @discardableResult
    public func create(in space: Space, name: String, color: StorageColor?, isFreezer: Bool) throws -> StorageLocation {
        guard !space.isGone else { throw ServiceError.notFound }
        try ensureEditable(space)
        let value = try validatedName(name)
        let nextOrder = (try locations(in: space).map { Int($0.sortOrder) }.max() ?? -1) + 1

        let location = spaceStore.insert(StorageLocation.self, in: space, by: userRecordName)
        location.space = space
        location.name = value
        location.color = color?.rawValue
        location.isFreezer = isFreezer
        location.sortOrder = numericCast(nextOrder)
        try context.save()
        return location
    }

    public func update(_ location: StorageLocation, name: String, color: StorageColor?, isFreezer: Bool) throws {
        _ = try editableSpace(of: location)
        location.name = try validatedName(name)
        location.color = color?.rawValue
        location.isFreezer = isFreezer
        location.stamp(by: userRecordName)
        try context.save()
    }

    public func rename(_ location: StorageLocation, to name: String) throws {
        _ = try editableSpace(of: location)
        location.name = try validatedName(name)
        location.stamp(by: userRecordName)
        try context.save()
    }

    public func setOrder(_ ordered: [StorageLocation]) throws {
        for location in ordered { _ = try editableSpace(of: location) }
        for (index, location) in ordered.enumerated() where Int(location.sortOrder) != index {
            location.sortOrder = numericCast(index)
            location.stamp(by: userRecordName)
        }
        if context.hasChanges { try context.save() }
    }

    public func delete(_ location: StorageLocation) throws {
        _ = try editableSpace(of: location)
        let items = try context.fetchEntities(InventoryItem.self, where: NSPredicate(format: "storageLocation == %@", location))
        for item in items {
            item.storageLocation = nil
            item.stamp(by: userRecordName)
        }
        context.delete(location)
        try context.save()
    }

    public func deletion(of location: StorageLocation, pending: PendingDeletions) throws -> UndoableAction {
        _ = try editableSpace(of: location)
        return pending.deletion(of: location.publicId, title: UndoTitle.removed(location.name)) {
            // Strong capture on purpose: a weak self is nil at commit when the service was built just for this call (P2-04).
            guard !location.isGone else { return }
            try self.delete(location)
        }
    }

    // MARK: Helpers

    private func editableSpace(of location: StorageLocation) throws -> Space {
        guard !location.isGone, let space = location.space else { throw ServiceError.notFound }
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
        return space
    }

    private func ensureEditable(_ space: Space) throws {
        guard canEditSpace(space) else { throw ServiceError.readOnlySpace }
    }

    private func validatedName(_ name: String) throws -> String {
        guard let value = name.nilIfBlank else { throw ServiceError.nameRequired }
        return value
    }
}
