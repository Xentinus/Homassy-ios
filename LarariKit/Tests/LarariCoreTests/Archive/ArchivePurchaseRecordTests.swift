import CoreData
import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Archive purchase records")
struct ArchivePurchaseRecordTests {
    let stack: ArchiveTestStack
    init() throws { stack = try ArchiveTestStack() }

    static let sparRecordID = UUID(uuidString: "F7000000-0000-4000-8000-000000000001")!
    static let plainRecordID = UUID(uuidString: "F7000000-0000-4000-8000-000000000002")!

    /// The sample plus two milk purchases: one at Spar linked to the milk stock item, one without a store.
    static func sampleWithPurchases() -> ArchiveContents {
        var contents = ArchiveSamples.sampleV1
        let meta = contents.data.products[0]
        contents.data.purchaseRecords = [
            PurchaseRecordDTO(publicId: sparRecordID, createdAt: meta.createdAt, updatedAt: meta.updatedAt,
                              createdBy: meta.createdBy, updatedBy: meta.updatedBy, product: ArchiveSamples.milkID,
                              shoppingLocation: ArchiveSamples.sparID, inventoryItem: ArchiveSamples.milkItemID,
                              quantity: DecimalString(2), unit: .liter, price: DecimalString(899),
                              currency: "HUF", purchasedAt: ArchiveTestStack.date("2026-09-10T10:00:00Z")),
            PurchaseRecordDTO(publicId: plainRecordID, createdAt: meta.createdAt, updatedAt: meta.updatedAt,
                              createdBy: meta.createdBy, updatedBy: meta.updatedBy, product: ArchiveSamples.milkID,
                              shoppingLocation: nil, inventoryItem: nil, quantity: DecimalString(1), unit: .liter,
                              price: DecimalString(Decimal(string: "479.5")!), currency: "HUF", purchasedAt: nil),
        ]
        contents.manifest.counts = contents.data.counts
        return contents
    }

    @Test func exportWritesPurchaseRecords() throws {
        let seeded = try stack.seedHousehold()
        let inventory = InventoryService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user)
        try inventory.recordPurchase(product: seeded.milk, quantity: 2, unit: .liter, price: 899, currency: "HUF",
                                     store: seeded.spar, purchasedAt: ArchiveTestStack.date("2026-09-10T10:00:00Z"),
                                     inventoryItem: seeded.milkItem)
        let contents = try ArchiveExporter(context: stack.context, appVersion: "1.0").snapshot(of: seeded.space).contents
        let record = try #require(contents.data.purchaseRecords.first)
        #expect(contents.data.purchaseRecords.count == 1)
        #expect(contents.manifest.counts.purchaseRecords == 1)
        #expect(record.product == seeded.milk.publicId)
        #expect(record.shoppingLocation == seeded.spar.publicId)
        #expect(record.inventoryItem == seeded.milkItem.publicId)
        #expect(record.price?.value == 899)
        #expect(record.quantity.value == 2)
    }

    @Test func importBringsThePriceHistoryIntoANewSpace() throws {
        let url = try stack.writeArchive(Self.sampleWithPurchases())
        let result = try stack.importer().importArchive(url: url, mode: .asNewSpace(name: "Másolat"))
        let records = try stack.fetch(PurchaseRecord.self, "product.space == %@", result.space)
        #expect(records.count == 2)
        let spar = try #require(records.first { $0.shoppingLocation != nil })
        #expect(spar.product?.name == "Tej")
        #expect(spar.shoppingLocation?.name == "Spar Market")
        #expect(spar.inventoryItem?.product == spar.product)
        #expect(spar.price == 899)
        #expect(!ArchiveSamples.allIDs.contains(spar.publicId) && spar.publicId != Self.sparRecordID)
        #expect(records.first { $0.shoppingLocation == nil }?.price == Decimal(string: "479.5")!)
        #expect(result.counts[.purchaseRecords] == EntityImportCounts(toCreate: 2))
    }

    @Test func anOlderFileWithoutPurchaseRecordsStillDecodes() throws {
        let encoded = try ArchiveCodec.encode(Self.sampleWithPurchases())
        var data = try #require(try JSONSerialization.jsonObject(with: encoded.data) as? [String: Any])
        data["purchaseRecords"] = nil
        var manifest = try #require(try JSONSerialization.jsonObject(with: encoded.manifest) as? [String: Any])
        var counts = manifest["counts"] as? [String: Any] ?? [:]
        counts["purchaseRecords"] = nil
        manifest["counts"] = counts
        let decoded = try ArchiveCodec.decode(manifest: try JSONSerialization.data(withJSONObject: manifest),
                                              data: try JSONSerialization.data(withJSONObject: data))
        #expect(decoded.data.purchaseRecords.isEmpty)
        #expect(decoded.manifest.counts.purchaseRecords == 0)
    }

    @Test func aDanglingProductIsRejected() {
        var data = Self.sampleWithPurchases().data
        data.purchaseRecords[0].product = UUID()
        #expect(throws: ArchiveError.brokenReference(entity: .purchaseRecords, publicId: Self.sparRecordID,
                                                     field: "product")) {
            try ArchiveValidator.validate(data)
        }
    }

    @Test func purchasesFollowTheirProductAndLoseStockLeftOut() throws {
        let sample = Self.sampleWithPurchases().data
        let onlyProducts = sample.filtered(by: ArchiveSelection(groups: [.products]))
        #expect(onlyProducts.data.purchaseRecords.count == 2)
        #expect(onlyProducts.data.purchaseRecords.allSatisfy { $0.inventoryItem == nil })
        #expect(onlyProducts.data.shoppingLocations.map(\.publicId) == [ArchiveSamples.sparID])   // brought along
        try ArchiveValidator.validate(onlyProducts.data)

        let flourOnly = sample.filtered(by: ArchiveSelection(groups: [.products, .stock],
                                                             productIDs: [ArchiveSamples.flourID]))
        #expect(flourOnly.data.purchaseRecords.isEmpty)
    }
}
