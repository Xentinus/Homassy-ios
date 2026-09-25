import Foundation
import Testing
@testable import HomassyCore

@Suite("Archive selection")
struct ArchiveSelectionTests {
    let sample = ArchiveSamples.sampleV1.data

    private func filter(_ groups: Set<ArchiveSelection.Group>, products: Set<UUID>? = nil) -> ArchiveFilterResult {
        sample.filtered(by: ArchiveSelection(groups: groups, productIDs: products))
    }

    @Test func everythingKeepsTheArchive() {
        let result = sample.filtered(by: .everything)
        #expect(result.data == sample)
        #expect(result.autoIncluded.isEmpty)
        #expect(result.unlinkedListItems == 0)
        #expect(!result.isEmpty)
    }

    @Test func productsOnly() {
        let result = filter([.products])
        #expect(result.data.products.map(\.publicId) == sample.products.map(\.publicId))
        #expect(result.data.space == sample.space)
        #expect(result.data.inventoryItems.isEmpty)
        #expect(result.data.consumptionLogs.isEmpty)
        #expect(result.data.inventoryEvents.isEmpty)
        #expect(result.data.storageLocations.isEmpty)
        #expect(result.data.shoppingLocations.isEmpty)
        #expect(result.data.shoppingLists.isEmpty)
        #expect(result.data.shoppingListItems.isEmpty)
        #expect(result.data.members.isEmpty)
        #expect(result.autoIncluded.isEmpty)
    }

    @Test func stockFollowsTheChosenProductsAndBringsItsPlaces() {
        let result = filter([.products, .stock], products: [ArchiveSamples.milkID])
        #expect(result.data.products.map(\.publicId) == [ArchiveSamples.milkID])
        #expect(result.data.inventoryItems.map(\.publicId) == [ArchiveSamples.milkItemID])
        #expect(result.data.consumptionLogs.map(\.publicId) == [ArchiveSamples.milkLogID])
        #expect(result.data.inventoryEvents.count == 3)
        #expect(result.data.inventoryEvents.allSatisfy { $0.product == ArchiveSamples.milkID })
        #expect(result.data.storageLocations.map(\.publicId) == [ArchiveSamples.fridgeID])
        #expect(result.data.shoppingLocations.map(\.publicId) == [ArchiveSamples.sparID])
        #expect(result.autoIncluded == [.storageLocations: 1, .shoppingLocations: 1])
    }

    @Test func stockWithoutPlacesNeedsNoAutomaticAdditions() {
        let result = filter([.products, .stock], products: [ArchiveSamples.flourID])
        #expect(result.data.inventoryItems.map(\.publicId) == [ArchiveSamples.flourItemID])
        #expect(result.data.consumptionLogs.isEmpty)
        #expect(result.data.inventoryEvents.map(\.publicId) == [ArchiveSamples.flourAddedEventID])
        #expect(result.data.storageLocations.isEmpty)
        #expect(result.autoIncluded.isEmpty)
    }

    @Test func selectedPlaceGroupsAreNotCountedAsAutomatic() {
        let result = filter([.products, .stock, .storageLocations, .shoppingLocations])
        #expect(result.data.storageLocations.count == 1)
        #expect(result.autoIncluded.isEmpty)
    }

    @Test func listItemsOfProductsLeftOutArriveUnlinkedUnderTheProductName() throws {
        let result = filter([.shoppingLists])
        #expect(result.data.shoppingLists.map(\.publicId) == [ArchiveSamples.weeklyListID])
        #expect(result.data.shoppingListItems.count == 2)
        let milk = try #require(result.data.shoppingListItems.first { $0.publicId == ArchiveSamples.milkListItemID })
        #expect(milk.product == nil)
        #expect(milk.customName == "Tej")
        #expect(milk.note == "Laktózmentes")
        let bread = try #require(result.data.shoppingListItems.first { $0.publicId == ArchiveSamples.breadListItemID })
        #expect(bread.customName == "Kenyér")
        #expect(result.unlinkedListItems == 1)
        #expect(result.data.shoppingLocations.map(\.publicId) == [ArchiveSamples.sparID])
        #expect(result.autoIncluded == [.shoppingLocations: 1])
    }

    @Test func listItemsKeepTheirProductWhenItIsImported() {
        let result = filter([.products, .shoppingLists], products: [ArchiveSamples.milkID])
        #expect(result.data.shoppingListItems.first { $0.publicId == ArchiveSamples.milkListItemID }?.product
                == ArchiveSamples.milkID)
        #expect(result.unlinkedListItems == 0)
    }

    @Test func stockWithoutProductsIsEmpty() {
        let result = filter([.stock])
        #expect(result.data.inventoryItems.isEmpty)
        #expect(result.isEmpty)
        #expect(filter([.products, .stock], products: []).isEmpty)
    }

    @Test func nothingSelectedIsEmpty() {
        #expect(filter([]).isEmpty)
        #expect(!filter([.members]).isEmpty)
    }

    @Test func filteredDataAlwaysValidates() throws {
        let selections: [ArchiveSelection] = [
            .everything,
            ArchiveSelection(groups: [.products]),
            ArchiveSelection(groups: [.products, .stock], productIDs: [ArchiveSamples.milkID]),
            ArchiveSelection(groups: [.shoppingLists]),
            ArchiveSelection(groups: [.stock, .shoppingLists, .members], productIDs: [ArchiveSamples.flourID]),
            ArchiveSelection(groups: [.products, .stock, .shoppingLists], productIDs: [ArchiveSamples.flourID]),
        ]
        for selection in selections {
            try ArchiveValidator.validate(sample.filtered(by: selection).data)
        }
    }
}

@Suite("Archive selection picks")
struct ArchiveSelectionPickTests {
    let sample = ArchiveSamples.sampleV1.data

    @Test func pickedMembersOnly() {
        let result = sample.filtered(by: ArchiveSelection(groups: [.members], picks: [.members: [ArchiveSamples.annaMemberID]]))
        #expect(result.data.members.map(\.publicId) == [ArchiveSamples.annaMemberID])
    }

    @Test func pickedListsBringOnlyTheirItems() {
        let none = sample.filtered(by: ArchiveSelection(groups: [.shoppingLists], picks: [.shoppingLists: []]))
        #expect(none.data.shoppingLists.isEmpty)
        #expect(none.data.shoppingListItems.isEmpty)
        #expect(none.isEmpty)

        let weekly = sample.filtered(by: ArchiveSelection(groups: [.shoppingLists],
                                                          picks: [.shoppingLists: [ArchiveSamples.weeklyListID]]))
        #expect(weekly.data.shoppingListItems.count == 2)
    }

    @Test func unpickedPlacesStillComeWhenStockNeedsThem() {
        let selection = ArchiveSelection(groups: [.products, .stock, .storageLocations, .shoppingLocations],
                                         picks: [.storageLocations: [], .shoppingLocations: []])
        let result = sample.filtered(by: selection)
        #expect(result.data.storageLocations.map(\.publicId) == [ArchiveSamples.fridgeID])
        #expect(result.data.shoppingLocations.map(\.publicId) == [ArchiveSamples.sparID])
        #expect(result.autoIncluded == [.storageLocations: 1, .shoppingLocations: 1])
    }

    @Test func pickedPlacesAreNotCountedAsAutomatic() {
        let selection = ArchiveSelection(groups: [.products, .stock, .storageLocations],
                                         picks: [.storageLocations: [ArchiveSamples.fridgeID]])
        let result = sample.filtered(by: selection)
        #expect(result.data.storageLocations.map(\.publicId) == [ArchiveSamples.fridgeID])
        #expect(result.autoIncluded[.storageLocations] == nil)
    }

    @Test func unpickedStoresWithoutReferencesStayOut() {
        let result = sample.filtered(by: ArchiveSelection(groups: [.shoppingLocations], picks: [.shoppingLocations: []]))
        #expect(result.data.shoppingLocations.isEmpty)
        #expect(result.isEmpty)
    }

    @Test func productIDsIsThePickOfProducts() {
        var selection = ArchiveSelection(groups: [.products], productIDs: [ArchiveSamples.milkID])
        #expect(selection.picks[.products] == [ArchiveSamples.milkID])
        selection.productIDs = nil
        #expect(selection.picks[.products] == nil)
    }

    @Test func pickedSubsetsValidate() throws {
        let selection = ArchiveSelection(groups: Set(ArchiveSelection.Group.allCases),
                                         picks: [.products: [ArchiveSamples.flourID], .storageLocations: [],
                                                 .shoppingLocations: [], .shoppingLists: [ArchiveSamples.weeklyListID],
                                                 .members: []])
        try ArchiveValidator.validate(sample.filtered(by: selection).data)
    }
}
