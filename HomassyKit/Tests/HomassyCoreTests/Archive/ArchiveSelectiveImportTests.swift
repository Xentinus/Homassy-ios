import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Archive selective import")
struct ArchiveSelectiveImportTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    @Test func previewCountsOnlyTheSelection() throws {
        let importer = stack.importer()
        let loaded = try importer.read(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        let selection = ArchiveSelection(groups: [.products, .stock], productIDs: [ArchiveSamples.milkID])
        let preview = try importer.preview(loaded, selection: selection)

        #expect(preview.counts(for: .products) == EntityImportCounts(toCreate: 1))
        #expect(preview.counts(for: .inventoryItems) == EntityImportCounts(toCreate: 1))
        #expect(preview.counts(for: .inventoryEvents) == EntityImportCounts(toCreate: 3))
        #expect(preview.counts(for: .members) == EntityImportCounts())
        #expect(preview.counts(for: .shoppingLists) == EntityImportCounts())
        #expect(preview.autoIncluded == [.storageLocations: 1, .shoppingLocations: 1])
        #expect(preview.unlinkedListItems == 0)
        #expect(!stack.context.hasChanges)
    }

    @Test func importWritesOnlyTheSelection() throws {
        let importer = stack.importer()
        let loaded = try importer.read(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        let space = try importer.importArchive(loaded, mode: .asNewSpace(name: "Csak tej"),
                                               selection: ArchiveSelection(groups: [.products, .shoppingLists],
                                                                           productIDs: [ArchiveSamples.flourID])).space

        #expect(try stack.fetch(Product.self, "space == %@", space).map(\.name) == ["Liszt"])
        #expect(try stack.fetch(InventoryItem.self, "product.space == %@", space).isEmpty)
        #expect(try stack.fetch(Member.self, "space == %@", space).isEmpty)
        #expect(try stack.fetch(StorageLocation.self, "space == %@", space).isEmpty)
        let listItems = try stack.fetch(ShoppingListItem.self, "shoppingList.space == %@", space)
        #expect(listItems.count == 2)
        let milk = try #require(listItems.first { $0.customName == "Tej" })
        #expect(milk.product == nil)
        #expect(try stack.fetch(ShoppingLocation.self, "space == %@", space).map(\.name) == ["Spar Market"])
    }

    @Test func mergeWithASelectionOnlyTouchesTheSubset() throws {
        let home = stack.makeSpace(name: "Otthon")
        try stack.context.save()
        let importer = stack.importer()
        let loaded = try importer.read(url: try stack.writeArchive(ArchiveSamples.sampleV1))
        let result = try importer.importArchive(loaded, mode: .merge(into: home),
                                                selection: ArchiveSelection(groups: [.members]))
        #expect(result.counts[.members] == EntityImportCounts(toCreate: 2))
        #expect(result.counts[.products] == EntityImportCounts())
        #expect(try stack.fetch(Member.self, "space == %@", home).count == 2)
        #expect(try stack.fetch(Product.self, "space == %@", home).isEmpty)
    }

    @Test func urlImportStillTakesEverything() throws {
        let url = try stack.writeArchive(ArchiveSamples.sampleV1)
        let space = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Minden")).space
        #expect(try stack.fetch(Product.self, "space == %@", space).count == 2)
        #expect(try stack.fetch(InventoryEvent.self, "product.space == %@", space).count == 4)
    }
}
