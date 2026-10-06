import CoreData
import Foundation

public struct ForeignChange: Sendable, Equatable {
    public let publicId: UUID
    public let entityName: String
    public let userRecordName: String

    public init(publicId: UUID, entityName: String, userRecordName: String) {
        self.publicId = publicId
        self.entityName = entityName
        self.userRecordName = userRecordName
    }
}

public struct HistoryBatch: Sendable, Equatable {
    public var changedObjectIDs: Set<NSManagedObjectID> = []
    public var insertedByEntity: [String: Set<NSManagedObjectID>] = [:]
    public var changedEntityNames: Set<String> = []
    public var foreignChanges: [ForeignChange] = []

    public init() {}
    public var isEmpty: Bool { changedObjectIDs.isEmpty }
}

@MainActor
public final class HistoryProcessor {
    public static let appTransactionAuthor = PersistenceController.transactionAuthor

    private let container: NSPersistentContainer
    private let tokens: HistoryTokenStore
    private let currentUserRecordName: String
    private let deduplicateStore: NSPersistentStore?
    private let attributionMaxAge: TimeInterval
    private let now: @MainActor () -> Date

    public init(container: NSPersistentContainer, tokens: HistoryTokenStore, currentUserRecordName: String,
                deduplicateStore: NSPersistentStore?, attributionMaxAge: TimeInterval = 600,
                now: @escaping @MainActor () -> Date = { .now }) {
        self.container = container
        self.tokens = tokens
        self.currentUserRecordName = currentUserRecordName
        self.deduplicateStore = deduplicateStore
        self.attributionMaxAge = attributionMaxAge
        self.now = now
    }

    public func process(store: NSPersistentStore) throws -> HistoryBatch {
        let context = container.viewContext
        let storeID = store.identifier ?? store.url?.absoluteString ?? "store"
        let lastToken = tokens.token(for: storeID)

        let fetched: [NSPersistentHistoryTransaction]
        do {
            fetched = try fetchTransactions(after: lastToken, in: store, context: context)
        } catch let error as NSError where error.code == NSPersistentHistoryTokenExpiredError {
            tokens.setToken(nil, for: storeID)
            return try process(store: store)
        }

        // The app's own saves are already in the view context; they only move the token forward.
        let transactions = fetched.filter { $0.author != Self.appTransactionAuthor }
        var batch = HistoryBatch()
        var candidates = Set<NSManagedObjectID>()
        for transaction in transactions {
            context.mergeChanges(fromContextDidSave: transaction.objectIDNotification())
            for change in transaction.changes ?? [] {
                let id = change.changedObjectID
                let entityName = id.entity.name ?? ""
                batch.changedObjectIDs.insert(id)
                batch.changedEntityNames.insert(entityName)
                switch change.changeType {
                case .insert:
                    batch.insertedByEntity[entityName, default: []].insert(id)
                    candidates.insert(id)
                case .update:
                    candidates.insert(id)
                case .delete:
                    break
                @unknown default:
                    break
                }
            }
        }

        if let last = fetched.last?.token {
            tokens.setToken(last, for: storeID)
        } else if lastToken == nil,
                  let current = container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: [store]) {
            tokens.setToken(current, for: storeID)
        }

        if let deduplicateStore, deduplicateStore === store {
            for entityName in batch.insertedByEntity.keys.sorted() {
                _ = try Deduplicator.mergeDuplicates(entityName: entityName, in: context)
            }
            if context.hasChanges { try context.save() }
        }

        if lastToken != nil {
            batch.foreignChanges = foreignChanges(among: candidates, in: context)
        }
        return batch
    }

    private func fetchTransactions(after token: NSPersistentHistoryToken?, in store: NSPersistentStore,
                                   context: NSManagedObjectContext) throws -> [NSPersistentHistoryTransaction] {
        // Every transaction, the app's own included, so the token moves past them; `process` filters by author.
        let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
        request.affectedStores = [store]
        request.resultType = .transactionsAndChanges
        let result = try context.execute(request) as? NSPersistentHistoryResult
        return result?.result as? [NSPersistentHistoryTransaction] ?? []
    }

    private func foreignChanges(among ids: Set<NSManagedObjectID>, in context: NSManagedObjectContext) -> [ForeignChange] {
        let reference = now()
        return ids.compactMap { id -> ForeignChange? in
            guard let object = try? context.existingObject(with: id), !object.isDeleted,
                  let entity = object as? any LarariEntity else { return nil }
            let author = entity.updatedBy
            guard !author.isEmpty, author != currentUserRecordName,
                  reference.timeIntervalSince(entity.updatedAt) <= attributionMaxAge else { return nil }
            return ForeignChange(publicId: entity.publicId, entityName: id.entity.name ?? "", userRecordName: author)
        }
        .sorted { $0.publicId.uuidString < $1.publicId.uuidString }
    }
}
