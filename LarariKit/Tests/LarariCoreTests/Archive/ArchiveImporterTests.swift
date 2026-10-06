import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Archive importer")
struct ArchiveImporterTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    private func products(in space: Space) throws -> [Product] {
        try stack.fetch(Product.self, "space == %@", space)
    }

    private func product(_ name: String, in space: Space) throws -> Product {
        try #require(try products(in: space).first { $0.name == name })
    }

    // MARK: Preview

    @Test func previewAsNewSpaceCountsEverythingAsNew() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let preview = try stack.importer().preview(url: url)

        #expect(!preview.isMerge)
        #expect(preview.manifest.spaceName == "Otthon")
        for entity in ArchiveEntity.allCases {
            let expected = ArchiveSamples.sampleV1.manifest.counts[entity]
            #expect(preview.counts(for: entity) == EntityImportCounts(toCreate: expected), "\(entity)")
        }
        #expect(preview.totalToUpdate == 0)
        #expect(preview.totalToCreate == 16)
        #expect(!stack.context.hasChanges)
        #expect(try stack.spaceCount() == 0)
    }

    // MARK: As a new space

    @Test func importAsNewSpaceCreatesAnUnsharedHouseholdWithFreshIds() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let result = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "  Otthon (másolat) "))
        let space = result.space

        #expect(space.name == "Otthon (másolat)")
        #expect(space.kind == .household)
        #expect(!stack.spaceStore.isShared(space))
        #expect(space.objectID.persistentStore == stack.persistence.privateStore)
        #expect(!stack.context.hasChanges)
        #expect(!ArchiveSamples.allIDs.contains(space.publicId))

        let all = try products(in: space)
        #expect(all.map(\.name).sorted() == ["Liszt", "Tej"])
        #expect(all.allSatisfy { !ArchiveSamples.allIDs.contains($0.publicId) })

        let milk = try product("Tej", in: space)
        #expect(milk.brand == "Mizo")
        #expect(milk.url == "https://www.mizo.hu/termekek/tej")
        #expect(milk.createdBy == "_owner0001")
        #expect(milk.updatedBy == "_member0002")
        #expect(milk.updatedAt == ArchiveTestStack.date("2026-09-01T08:15:00+02:00"))
        #expect(try product("Liszt", in: space).url == nil)

        let items = try stack.fetch(InventoryItem.self, "product.space == %@", space)
        #expect(items.count == 2)
        let milkItem = try #require(items.first { $0.product == milk })
        #expect(milkItem.quantity == ArchiveTestStack.decimal("1.5"))
        #expect(milkItem.storageLocation?.name == "Hűtő")
        #expect(milkItem.storageLocation?.space == space)
        #expect(milkItem.shoppingLocation?.name == "Spar Market")
        let flourItem = try #require(items.first { $0.product?.name == "Liszt" })
        #expect(flourItem.quantity == ArchiveTestStack.decimal("0.1"))

        let log = try #require(try stack.fetch(ConsumptionLog.self, "inventoryItem.product.space == %@", space).first)
        #expect(log.inventoryItem == milkItem)

        let listItems = try stack.fetch(ShoppingListItem.self, "shoppingList.space == %@", space)
        #expect(listItems.count == 2)
        #expect(listItems.first { $0.product != nil }?.product == milk)
        #expect(listItems.first { $0.customName == "Kenyér" }?.isPurchased == true)
        #expect(Set(listItems.compactMap { $0.shoppingList?.name }) == ["Heti bevásárlás"])

        let members = try stack.fetch(Member.self, "space == %@", space)
        #expect(Set(members.map(\.displayName)) == ["Béla", "Anna"])
        #expect(result.counts[.products] == EntityImportCounts(toCreate: 2))
        #expect(result.counts[.inventoryEvents] == EntityImportCounts(toCreate: 4))
    }

    @Test func inventoryEventsAreImportedAndLinked() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let space = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Előzmények")).space
        let milk = try product("Tej", in: space)
        let events = try stack.fetch(InventoryEvent.self, "product.space == %@", space)
        #expect(events.count == 4)
        #expect(events.allSatisfy { !ArchiveSamples.allIDs.contains($0.publicId) })

        let milkEvents = events.filter { $0.product == milk }
        #expect(milkEvents.count == 3)
        let consumed = try #require(milkEvents.first { $0.kind == .consumed })
        #expect(consumed.quantity == ArchiveTestStack.decimal("0.5"))
        #expect(consumed.unit == .liter)
        #expect(consumed.fromLocationName == "Hűtő")
        #expect(consumed.occurredAt == ArchiveTestStack.date("2026-09-21T07:30:00+02:00"))
        #expect(consumed.createdBy == "_member0002")
        #expect(consumed.inventoryItem?.product == milk)
        let deleted = try #require(milkEvents.first { $0.kind == .deleted })
        #expect(deleted.inventoryItem == nil)
    }

    @Test func importingTwiceAsNewSpaceGivesIndependentSpaces() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let first = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "A")).space
        let second = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "B")).space

        #expect(try stack.spaceCount() == 2)
        let ids = try products(in: first).map(\.publicId) + products(in: second).map(\.publicId)
        #expect(Set(ids).count == 4)
        let firstOrder: Int = numericCast(first.sortOrder)
        let secondOrder: Int = numericCast(second.sortOrder)
        #expect(secondOrder > firstOrder)
    }

    @Test func emptyNameIsRejectedAndNothingIsWritten() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        #expect(throws: ServiceError.nameRequired) {
            try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "   "))
        }
        #expect(try stack.spaceCount() == 0)
        #expect(!stack.context.hasChanges)
    }

    @Test func imagesAreImported() throws {
        var contents = ArchiveSamples.sampleV1
        let photo = Data(repeating: 0x42, count: 777)
        let ref = ArchiveImages.reference(for: photo)
        contents.data.products[0].image = ref
        contents.data.members[1].avatar = ref
        let url = try stack.writeArchive(contents, images: [ref: photo])

        let space = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Képes")).space
        #expect(try product("Tej", in: space).image == photo)
        #expect(try stack.fetch(Member.self, "space == %@", space).first { $0.displayName == "Anna" }?.avatar == photo)
        #expect(try product("Liszt", in: space).image == nil)
    }

    // MARK: Merge

    @Test func mergeNewerWinsOlderAndEqualKeepLocalMissingIsCreatedNothingDeleted() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        let importer = stack.importer()
        // First merge into an empty space keeps the archive's publicIds.
        try importer.importArchive(url: try stack.writeArchive(ArchiveSamples.sampleV1), mode: .merge(into: home))
        #expect(try product("Tej", in: home).publicId == ArchiveSamples.milkID)

        let salt: Product = stack.insert(Product.self, in: home)
        salt.space = home
        salt.name = "Só"
        try stack.context.save()

        var changed = ArchiveSamples.sampleV1
        let milkIndex = try #require(changed.data.products.firstIndex { $0.publicId == ArchiveSamples.milkID })
        let flourIndex = try #require(changed.data.products.firstIndex { $0.publicId == ArchiveSamples.flourID })
        let newer = ArchiveTestStack.date("2026-09-22T09:00:00+02:00")
        changed.data.products[milkIndex].name = "Tej 2,8%"
        changed.data.products[milkIndex].updatedAt = newer                       // newer → update
        changed.data.products[flourIndex].name = "Liszt RÉGI"
        changed.data.products[flourIndex].updatedAt = ArchiveTestStack.date("2026-01-01T00:00:00+01:00") // older → keep
        changed.data.storageLocations[0].name = "Hűtő (azonos)"                  // equal updatedAt → keep
        var sugar = changed.data.products[flourIndex]
        sugar.publicId = try #require(UUID(uuidString: "30000000-0000-4000-8000-000000000099"))
        sugar.name = "Cukor"
        changed.data.products.append(sugar)                                     // missing → create
        let url = try stack.writeArchive(changed)

        let preview = try importer.preview(url: url, mergeInto: home)
        #expect(preview.isMerge)
        #expect(preview.counts(for: .products) == EntityImportCounts(toCreate: 1, toUpdate: 1, unchanged: 1))
        #expect(preview.counts(for: .storageLocations) == EntityImportCounts(unchanged: 1))
        #expect(preview.counts(for: .inventoryItems) == EntityImportCounts(unchanged: 2))
        #expect(preview.counts(for: .inventoryEvents) == EntityImportCounts(unchanged: 4))
        #expect(preview.totalToUpdate == 1)
        #expect(!stack.context.hasChanges)

        let result = try importer.importArchive(url: url, mode: .merge(into: home))
        #expect(result.space == home)
        #expect(result.counts[.products] == EntityImportCounts(toCreate: 1, toUpdate: 1, unchanged: 1))
        #expect(try products(in: home).map(\.name).sorted() == ["Cukor", "Liszt", "Só", "Tej 2,8%"])
        let milk = try product("Tej 2,8%", in: home)
        #expect(milk.updatedAt == newer)
        #expect(milk.publicId == ArchiveSamples.milkID)
        #expect(try stack.fetch(StorageLocation.self, "space == %@", home).map(\.name) == ["Hűtő"])
        #expect(try product("Cukor", in: home).publicId == sugar.publicId)
        #expect(home.name == "Otthon")
        #expect(try stack.spaceCount() == 1)
        #expect(try stack.fetch(InventoryItem.self, "product.space == %@", home).count == 2)
        #expect(try stack.fetch(InventoryEvent.self, "product.space == %@", home).count == 4)
    }

    @Test func mergeIntoAnotherSpaceGivesFreshIdsWhenTheyExistElsewhere() throws {
        let first = stack.makeSpace(name: "Első")
        let second = stack.makeSpace(name: "Második")
        try stack.context.save()
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        try stack.importer().importArchive(url: url, mode: .merge(into: first))

        let preview = try stack.importer().preview(url: url, mergeInto: second)
        #expect(preview.counts(for: .products) == EntityImportCounts(toCreate: 2))
        try stack.importer().importArchive(url: url, mode: .merge(into: second))

        #expect(Set(try products(in: first).map(\.publicId)) == [ArchiveSamples.milkID, ArchiveSamples.flourID])
        #expect(try products(in: second).allSatisfy { !ArchiveSamples.allIDs.contains($0.publicId) })
        let milkItem = try #require(try stack.fetch(InventoryItem.self, "product.space == %@", second)
            .first { $0.product?.name == "Tej" })
        #expect(milkItem.storageLocation?.space == second)
        let secondEvents = try stack.fetch(InventoryEvent.self, "product.space == %@", second)
        #expect(secondEvents.count == 4)
        #expect(secondEvents.allSatisfy { $0.inventoryItem == nil || $0.inventoryItem?.product?.space == second })
    }

    @Test func mergeUpdateRewiresReferences() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        try stack.importer().importArchive(url: try stack.writeArchive(ArchiveSamples.sampleV1), mode: .merge(into: home))

        var changed = ArchiveSamples.sampleV1
        changed.data.inventoryItems[1].storageLocation = ArchiveSamples.fridgeID
        changed.data.inventoryItems[1].updatedAt = ArchiveTestStack.date("2026-09-23T10:00:00+02:00")
        try stack.importer().importArchive(url: try stack.writeArchive(changed), mode: .merge(into: home))

        let flourItem = try #require(try stack.fetch(InventoryItem.self, "publicId == %@", ArchiveSamples.flourItemID as NSUUID).first)
        #expect(flourItem.storageLocation?.publicId == ArchiveSamples.fridgeID)
    }

    // MARK: Failure and rollback

    @Test func corruptedFileWritesNothing() throws {
        let url = stack.temporaryURL()
        try Data("PK\u{03}\u{04} this is not really a zip".utf8).write(to: url)
        let error = #expect(throws: ArchiveError.self) {
            try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "X"))
        }
        guard case .corrupted = error else {
            Issue.record("expected .corrupted, got \(String(describing: error))")
            return
        }
        #expect(try stack.spaceCount() == 0)
        #expect(!stack.context.hasChanges)
    }

    @Test func brokenReferenceWritesNothing() throws {
        var contents = ArchiveSamples.sampleV1
        contents.data.inventoryItems[0].product = UUID()
        let url = try stack.writeArchive(contents)
        #expect(throws: ArchiveError.brokenReference(entity: .inventoryItems,
                                                     publicId: ArchiveSamples.milkItemID, field: "product")) {
            try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "X"))
        }
        #expect(throws: ArchiveError.self) { try stack.importer().preview(url: url) }
        #expect(try stack.spaceCount() == 0)
        #expect(try stack.count(Product.self) == 0)
    }

    @Test func failureHalfwayRollsEverythingBack() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        let importer = stack.importer()
        importer.afterApplying = { entity in
            if entity == .inventoryEvents { throw ArchiveError.corrupted("injected") }
        }
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)

        #expect(throws: ArchiveError.corrupted("injected")) {
            try importer.importArchive(url: url, mode: .asNewSpace(name: "Új"))
        }
        #expect(!stack.context.hasChanges)
        #expect(try stack.spaceCount() == 1)
        #expect(try stack.count(Product.self) == 0)

        #expect(throws: ArchiveError.corrupted("injected")) {
            try importer.importArchive(url: url, mode: .merge(into: home))
        }
        #expect(!stack.context.hasChanges)
        #expect(try stack.count(Product.self) == 0)
        #expect(try stack.count(Member.self) == 0)
        #expect(try stack.count(InventoryEvent.self) == 0)
    }

    @Test func unsavedChangesBlockTheImport() throws {
        let space = stack.makeSpace(name: "Piszkos")      // inserted, not saved
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        #expect(throws: ArchiveError.unsavedChanges) {
            try stack.importer().importArchive(url: url, mode: .merge(into: space))
        }
        #expect(stack.context.hasChanges)                 // the pending change is untouched
    }

    // MARK: Round trip

    @Test func exportThenImportRoundTrips() throws {
        let seeded = try stack.seedHousehold()
        let exporter = ArchiveExporter(context: stack.context)
        let url = try exporter.export(space: seeded.space)
        let copy = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Másolat")).space

        let original = try exporter.snapshot(of: seeded.space).contents.data
        let imported = try exporter.snapshot(of: copy).contents.data
        #expect(imported.counts == original.counts)
        #expect(imported.counts.inventoryEvents == 2)
        #expect(imported.products.map(\.name).sorted() == original.products.map(\.name).sorted())
        #expect(Set(imported.products.compactMap(\.url)) == Set(original.products.compactMap(\.url)))
        #expect(Set(imported.inventoryItems.map(\.quantity)) == Set(original.inventoryItems.map(\.quantity)))
        #expect(Set(imported.inventoryEvents.map(\.kind)) == Set(original.inventoryEvents.map(\.kind)))
        #expect(Set(imported.products.compactMap(\.image)) == Set(original.products.compactMap(\.image)))
        #expect(Set(imported.products.map(\.publicId)).isDisjoint(with: original.products.map(\.publicId)))
    }

    @Test func containerHandsOutAnImporter() throws {
        let services = ServiceContainer(spaceStore: stack.spaceStore, context: stack.context,
                                        userRecordName: stack.user, persistence: stack.persistence)
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let importer = try #require(services.archive).makeImporter()
        #expect(try importer.importArchive(url: url, mode: .asNewSpace(name: "Másolat")).space.kind == .household)
    }
}
