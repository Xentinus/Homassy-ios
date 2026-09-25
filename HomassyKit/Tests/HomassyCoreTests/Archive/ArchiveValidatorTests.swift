import Foundation
import Testing
@testable import HomassyCore

@Suite("Archive validator")
struct ArchiveValidatorTests {
    @Test func sampleIsValid() throws {
        try ArchiveValidator.validate(ArchiveSamples.sampleV1.data)
    }

    @Test func duplicatePublicIdAcrossCollectionsIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.storageLocations[0].publicId = ArchiveSamples.milkID
        #expect(throws: ArchiveError.duplicatePublicId(ArchiveSamples.milkID)) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func duplicateEventIdIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.inventoryEvents[1].publicId = ArchiveSamples.milkItemID
        #expect(throws: ArchiveError.duplicatePublicId(ArchiveSamples.milkItemID)) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func missingRequiredReferenceIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.inventoryItems[0].product = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .inventoryItems,
                                                     publicId: ArchiveSamples.milkItemID, field: "product")) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func danglingOptionalReferenceIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.shoppingListItems[0].shoppingLocation = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .shoppingListItems,
                                                     publicId: ArchiveSamples.milkListItemID,
                                                     field: "shoppingLocation")) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func logWithUnknownItemIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.consumptionLogs[0].inventoryItem = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .consumptionLogs,
                                                     publicId: ArchiveSamples.milkLogID, field: "inventoryItem")) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func eventWithUnknownProductOrItemIsRejected() {
        var unknownProduct = ArchiveSamples.sampleV1.data
        unknownProduct.inventoryEvents[0].product = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .inventoryEvents,
                                                     publicId: ArchiveSamples.milkAddedEventID, field: "product")) {
            try ArchiveValidator.validate(unknownProduct)
        }

        var unknownItem = ArchiveSamples.sampleV1.data
        unknownItem.inventoryEvents[0].inventoryItem = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .inventoryEvents,
                                                     publicId: ArchiveSamples.milkAddedEventID, field: "inventoryItem")) {
            try ArchiveValidator.validate(unknownItem)
        }
    }

    @Test func listItemWithUnknownListIsRejected() {
        var data = ArchiveSamples.sampleV1.data
        data.shoppingListItems[1].list = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .shoppingListItems,
                                                     publicId: ArchiveSamples.breadListItemID, field: "list")) {
            try ArchiveValidator.validate(data)
        }
    }
}
