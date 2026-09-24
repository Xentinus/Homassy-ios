import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Deduplicator")
struct DeduplicatorTests {
    @Test func noDuplicatesDeletesNothing() throws {
        let f = try SpaceFixture()
        _ = f.make(Product.self, in: f.persistence.privateStore)
        _ = f.make(Product.self, in: f.persistence.privateStore)
        try f.context.save()

        #expect(try Deduplicator.mergeDuplicates(entityName: "Product", in: f.context) == 0)
        #expect(try f.count("Product") == 2)
    }

    @Test func keepsTheEarliestCreatedObject() throws {
        let f = try SpaceFixture()
        let id = UUID()
        let late = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: Date(timeIntervalSince1970: 300))
        let early = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: Date(timeIntervalSince1970: 100))
        let middle = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: Date(timeIntervalSince1970: 200))
        try f.context.save()

        let removed = try Deduplicator.mergeDuplicates(entityName: "Product", in: f.context)
        try f.context.save()

        #expect(removed == 2)
        #expect(try f.count("Product") == 1)
        #expect(!early.isDeleted && early.managedObjectContext != nil)
        #expect(late.managedObjectContext == nil)
        #expect(middle.managedObjectContext == nil)
    }

    @Test func tieOnCreatedAtKeepsTheSmallestObjectIDURI() throws {
        let f = try SpaceFixture()
        let id = UUID()
        let date = Date(timeIntervalSince1970: 500)
        let a = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: date)
        let b = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: date)
        try f.context.save()
        let expected = [a, b].min { $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString }!

        _ = try Deduplicator.mergeDuplicates(entityName: "Product", in: f.context)
        try f.context.save()

        let remaining = try f.context.fetch(NSFetchRequest<Product>(entityName: "Product"))
        #expect(remaining.map(\.objectID) == [expected.objectID])
    }

    @Test func repointsChildrenOfDeletedDuplicateSpace() throws {
        let f = try SpaceFixture()
        let id = UUID()
        let survivor = f.makeSpace("Flat", publicId: id, createdAt: Date(timeIntervalSince1970: 1))
        let duplicate = f.makeSpace("Flat", publicId: id, createdAt: Date(timeIntervalSince1970: 2))
        let product = f.make(Product.self, in: f.persistence.privateStore)
        product.space = duplicate
        let location = f.make(StorageLocation.self, in: f.persistence.privateStore)
        location.space = duplicate
        let ownProduct = f.make(Product.self, in: f.persistence.privateStore)
        ownProduct.space = survivor
        try f.context.save()

        #expect(try Deduplicator.mergeDuplicates(entityName: "Space", in: f.context) == 1)
        try f.context.save()

        #expect(try f.count("Space") == 1)
        #expect(try f.count("Product") == 2)
        #expect(try f.count("StorageLocation") == 1)
        #expect(product.space?.objectID == survivor.objectID)
        #expect(location.space?.objectID == survivor.objectID)
        #expect(ownProduct.space?.objectID == survivor.objectID)
    }

    @Test func neverMergesAcrossStores() throws {
        let f = try SpaceFixture()
        let id = UUID()
        _ = f.make(Product.self, in: f.persistence.privateStore, publicId: id)
        _ = f.make(Product.self, in: f.persistence.sharedStore, publicId: id)
        try f.context.save()

        #expect(try Deduplicator.mergeDuplicates(entityName: "Product", in: f.context) == 0)
        #expect(try f.count("Product") == 2)
    }

    @Test func handlesUnsavedObjects() throws {
        let f = try SpaceFixture()
        let id = UUID()
        _ = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: Date(timeIntervalSince1970: 1))
        _ = f.make(Product.self, in: f.persistence.privateStore, publicId: id, createdAt: Date(timeIntervalSince1970: 2))

        #expect(try Deduplicator.mergeDuplicates(entityName: "Product", in: f.context) == 1)
        try f.context.save()
        #expect(try f.count("Product") == 1)
    }
}
