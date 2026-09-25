import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
struct HistoryProcessorTests {
    let me = "_me"
    let container: NSPersistentContainer
    let store: NSPersistentStore
    let defaults: UserDefaults

    init() throws {
        (container, store) = try HistoryTestContainer.make()
        defaults = UserDefaults(suiteName: "HistoryProcessorTests-\(UUID().uuidString)")!
    }

    func makeProcessor(now: Date = .now) -> HistoryProcessor {
        HistoryProcessor(container: container, tokens: HistoryTokenStore(defaults: defaults),
                         currentUserRecordName: me, deduplicateStore: store, now: { now })
    }

    @Test func firstRunRecordsATokenButAttributesNothing() throws {
        let processor = makeProcessor()
        try HistoryTestContainer.importProduct(into: container, name: "Milk", updatedBy: "_anna")

        let first = try processor.process(store: store)
        #expect(first.changedObjectIDs.count == 1)
        #expect(first.foreignChanges.isEmpty)

        #expect(try processor.process(store: store).isEmpty)
    }

    @Test func foreignImportIsAttributedAndMerged() throws {
        let processor = makeProcessor()
        _ = try processor.process(store: store)                     // prime the token
        let id = try HistoryTestContainer.importProduct(into: container, name: "Milk", updatedBy: "_anna")

        let batch = try processor.process(store: store)

        #expect(batch.foreignChanges == [ForeignChange(publicId: id, entityName: "Product", userRecordName: "_anna")])
        #expect(batch.changedEntityNames == ["Product"])
        #expect(batch.insertedByEntity["Product"]?.count == 1)
        #expect(try HistoryTestContainer.products(with: id, in: container).count == 1)
    }

    @Test func ownChangesFromAnotherDeviceAreNotAttributed() throws {
        let processor = makeProcessor()
        _ = try processor.process(store: store)
        try HistoryTestContainer.importProduct(into: container, name: "Bread", updatedBy: me)

        let batch = try processor.process(store: store)

        #expect(batch.changedObjectIDs.count == 1)
        #expect(batch.foreignChanges.isEmpty)
    }

    @Test func appAuthoredTransactionsAreSkipped() throws {
        let processor = makeProcessor()
        _ = try processor.process(store: store)
        let product = NSEntityDescription.insertNewObject(forEntityName: "Product", into: container.viewContext) as! Product
        product.publicId = UUID()
        product.name = "Local"
        product.updatedBy = "_anna"
        product.updatedAt = .now
        try container.viewContext.save()

        #expect(try processor.process(store: store).isEmpty)
    }

    @Test func staleChangesAreNotAttributed() throws {
        let processor = makeProcessor()
        _ = try processor.process(store: store)
        try HistoryTestContainer.importProduct(into: container, name: "Old", updatedBy: "_anna",
                                               updatedAt: Date.now.addingTimeInterval(-3600))

        #expect(try processor.process(store: store).foreignChanges.isEmpty)
    }

    @Test func duplicatesFromImportAreMergedInThePrivateStore() throws {
        let processor = makeProcessor()
        _ = try processor.process(store: store)
        let id = UUID()
        try HistoryTestContainer.importProduct(into: container, name: "Milk", publicId: id, updatedBy: "_anna")
        try HistoryTestContainer.importProduct(into: container, name: "Milk", publicId: id, updatedBy: "_bea")

        _ = try processor.process(store: store)

        #expect(try HistoryTestContainer.products(with: id, in: container).count == 1)
    }

    @Test func noDeduplicationOutsideTheDeduplicateStore() throws {
        let processor = HistoryProcessor(container: container, tokens: HistoryTokenStore(defaults: defaults),
                                         currentUserRecordName: me, deduplicateStore: nil)
        _ = try processor.process(store: store)
        let id = UUID()
        try HistoryTestContainer.importProduct(into: container, name: "Milk", publicId: id, updatedBy: "_anna")
        try HistoryTestContainer.importProduct(into: container, name: "Milk", publicId: id, updatedBy: "_bea")

        _ = try processor.process(store: store)

        #expect(try HistoryTestContainer.products(with: id, in: container).count == 2)
    }

    @Test func tokenSurvivesANewProcessorInstance() throws {
        let first = makeProcessor()
        _ = try first.process(store: store)
        try HistoryTestContainer.importProduct(into: container, name: "Milk", updatedBy: "_anna")
        _ = try first.process(store: store)

        #expect(try makeProcessor().process(store: store).isEmpty)
    }

    @Test func tokenStoreRoundTrips() throws {
        let tokens = HistoryTokenStore(defaults: defaults)
        let token = try #require(container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: [store]))
        tokens.setToken(token, for: "store-a")
        #expect(HistoryTokenStore(defaults: defaults).token(for: "store-a") == token)
        #expect(tokens.token(for: "store-b") == nil)
        tokens.setToken(nil, for: "store-a")
        #expect(tokens.token(for: "store-a") == nil)
    }

    @Test func persistenceControllerMarksItsWritesAsApp() throws {
        let persistence = try PersistenceController(mode: .inMemory)
        #expect(persistence.viewContext.transactionAuthor == HistoryProcessor.appTransactionAuthor)
    }
}
