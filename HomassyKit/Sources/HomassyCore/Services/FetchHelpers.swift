import CoreData
import Foundation

extension NSManagedObjectContext {
    func fetchEntities<T: NSManagedObject>(_ type: T.Type, where predicate: NSPredicate? = nil,
                                           sortedBy sort: [NSSortDescriptor] = []) throws -> [T] {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        request.sortDescriptors = sort
        return try fetch(request)
    }

    func countEntities<T: NSManagedObject>(_ type: T.Type, where predicate: NSPredicate? = nil) throws -> Int {
        let request = NSFetchRequest<T>(entityName: String(describing: type))
        request.predicate = predicate
        return try count(for: request)
    }
}

extension NSManagedObject {
    /// Deleted in this context or no longer attached to one (e.g. removed by a remote change).
    var isGone: Bool { isDeleted || managedObjectContext == nil }
}

/// Finder-style ordering ("Item 2" before "Item 10"), case- and diacritic-aware.
func sortedByName<T>(_ values: [T], name: (T) -> String) -> [T] {
    values.sorted { name($0).localizedStandardCompare(name($1)) == .orderedAscending }
}

extension String {
    /// Trimmed of whitespace and newlines; `nil` when nothing is left.
    var nilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
