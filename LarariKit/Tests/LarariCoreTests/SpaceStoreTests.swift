import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("SpaceStore")
struct SpaceStoreTests {
    @Test func personalSpaceIDIsDeterministicUUIDv5() {
        #expect(SpaceStore.personalSpaceID(for: "_abc123") == UUID(uuidString: "1A3309F6-D53C-5A79-AF7B-593D4A5C844E"))
        #expect(SpaceStore.personalSpaceID(for: "_uiTestUser") == UUID(uuidString: "A6AE0835-8C8B-56EB-9793-22F9CDC4B613"))
        #expect(SpaceStore.personalSpaceID(for: "_other") == UUID(uuidString: "EF2AB863-D7DB-5D57-BC76-B92FE0D9B4B7"))
    }

    @Test func bootstrapCreatesPersonalSpaceInPrivateStore() throws {
        let f = try SpaceFixture()
        let space = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")

        #expect(space.kind == .personal)
        #expect(space.publicId == SpaceStore.personalSpaceID(for: "_abc123"))
        #expect(space.objectID.persistentStore === f.persistence.privateStore)
        #expect(["Personal", "Személyes", "Persönlich"].contains(space.name))
        #expect(space.createdBy == "_abc123")
        #expect(space.updatedBy == "_abc123")
        #expect(!space.objectID.isTemporaryID)
        #expect(!f.context.hasChanges)
    }

    @Test func bootstrapIsIdempotent() throws {
        let f = try SpaceFixture()
        let first = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let second = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")

        #expect(first.objectID == second.objectID)
        #expect(try f.count("Space") == 1)
    }

    @Test func bootstrapMergesDuplicatePersonalSpacesFromOtherDevices() throws {
        let f = try SpaceFixture()
        let id = SpaceStore.personalSpaceID(for: "_abc123")
        let older = f.makeSpace("Personal", kind: .personal, publicId: id, createdAt: Date(timeIntervalSince1970: 100))
        let newer = f.makeSpace("Personal", kind: .personal, publicId: id, createdAt: Date(timeIntervalSince1970: 200))
        let product = f.make(Product.self, in: f.persistence.privateStore)
        product.space = newer
        try f.context.save()

        let survivor = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")

        #expect(survivor.objectID == older.objectID)
        #expect(try f.count("Space") == 1)
        #expect(product.space?.objectID == older.objectID)
        #expect(!f.context.hasChanges)
    }

    @Test func allSpacesListsPersonalFirstThenHouseholdsBySortOrder() throws {
        let f = try SpaceFixture()
        _ = f.makeSpace("Beach house", sortOrder: 2)
        _ = f.makeSpace("Parents", sortOrder: 0, in: f.persistence.sharedStore)
        _ = f.makeSpace("Flat", sortOrder: 1)
        try f.context.save()
        _ = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")

        let names = try f.store.allSpaces().map(\.name)

        #expect(names.count == 4)
        #expect(names.dropFirst() == ["Parents", "Flat", "Beach house"])
        #expect(try f.store.allSpaces().first?.kind == .personal)
    }

    @Test func storeForSpaceIsTheStoreItLivesIn() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let joined = f.makeSpace("Parents", in: f.persistence.sharedStore)
        try f.context.save()

        #expect(f.store.store(for: personal) === f.persistence.privateStore)
        #expect(f.store.store(for: joined) === f.persistence.sharedStore)
    }

    @Test func insertCreatesStampedObjectInTheSpacesStore() throws {
        let f = try SpaceFixture()
        let joined = f.makeSpace("Parents", in: f.persistence.sharedStore)
        try f.context.save()
        let before = Date.now

        let product = f.store.insert(Product.self, in: joined, by: "_writer")
        product.space = joined
        try f.context.save()

        #expect(product.objectID.persistentStore === f.persistence.sharedStore)
        #expect(product.createdBy == "_writer")
        #expect(product.updatedBy == "_writer")
        #expect(product.createdAt >= before)
        #expect(product.updatedAt == product.createdAt)
        let other = f.store.insert(Product.self, in: joined, by: "_writer")
        #expect(other.publicId != product.publicId)
    }

    @Test func insertDoesNotSave() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        _ = f.store.insert(StorageLocation.self, in: personal, by: "_abc123")
        #expect(f.context.hasChanges)
    }

    @Test func isSharedFollowsTheShareLookup() throws {
        let f = try SpaceFixture()
        let personal = try f.store.bootstrapPersonalSpace(userRecordName: "_abc123")
        let shared = f.makeSpace("Flat")
        let unshared = f.makeSpace("Cabin")
        try f.context.save()
        f.sharing.markShared(shared)
        f.sharing.markShared(personal)

        #expect(f.store.isShared(shared))
        #expect(!f.store.isShared(unshared))
        #expect(!f.store.isShared(personal))   // Personal is never shareable
    }
}
