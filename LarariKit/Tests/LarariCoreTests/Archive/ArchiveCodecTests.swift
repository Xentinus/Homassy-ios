import Foundation
import Testing
@testable import LarariCore

enum ArchiveFixture {
    static func data(_ name: String) throws -> Data {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json",
                                          subdirectory: "Fixtures/sample-v1") else {
            throw ArchiveError.missingEntry("Fixtures/sample-v1/\(name).json")
        }
        return try Data(contentsOf: url)
    }

    /// Re-serialises a JSON object after `body` edits it. Used to simulate future or broken files.
    static func mutating(_ data: Data, _ body: (inout [String: Any]) -> Void) throws -> Data {
        guard var object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ArchiveError.corrupted("fixture is not an object")
        }
        body(&object)
        return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
    }
}

@Suite("Archive codec")
struct ArchiveCodecTests {
    @Test func fixtureDecodesToTheSample() throws {
        let contents = try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"),
                                               data: ArchiveFixture.data("data"))
        #expect(contents == ArchiveSamples.sampleV1)
        #expect(contents.manifest.counts == contents.data.counts)
    }

    @Test func encodeThenDecodeIsIdentity() throws {
        let files = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        let decoded = try ArchiveCodec.decode(manifest: files.manifest, data: files.data)
        #expect(decoded == ArchiveSamples.sampleV1)
        let text = String(decoding: files.manifest + files.data, as: UTF8.self)
        #expect(!text.contains("null"))          // absent optionals are omitted, never null
        #expect(!text.contains(#"\/"#))          // slashes are not escaped
    }

    @Test func encodingIsDeterministic() throws {
        let first = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        let second = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        #expect(first.manifest == second.manifest)
        #expect(first.data == second.data)
    }

    @Test func pointOneKilogramIsExact() throws {
        let tenth = try #require(Decimal(string: "0.1"))
        let json = try JSONEncoder().encode([DecimalString(tenth)])
        #expect(String(decoding: json, as: UTF8.self) == #"["0.1"]"#)
        let back = try JSONDecoder().decode([DecimalString].self, from: json)
        #expect(back.first?.value == tenth)

        let contents = try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"),
                                               data: ArchiveFixture.data("data"))
        let flour = try #require(contents.data.inventoryItems.first { $0.publicId == ArchiveSamples.flourItemID })
        #expect(flour.quantity.value == tenth)
        #expect(flour.unit == .kilogram)

        let encoded = String(decoding: try ArchiveCodec.encode(contents).data, as: UTF8.self)
        #expect(encoded.contains(#""quantity" : "0.1""#))
    }

    @Test(arguments: [#"["1,5"]"#, #"["abc"]"#, #"[0.1]"#, #"["1e3"]"#, #"[""]"#, #"[".5"]"#])
    func decimalRejectsNonCanonicalInput(_ json: String) {
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([DecimalString].self, from: Data(json.utf8))
        }
    }

    @Test func datesKeepTheirOffset() throws {
        let files = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        let data = String(decoding: files.data, as: UTF8.self)
        #expect(data.contains("2026-09-20T17:40:00.000+02:00"))   // summer time in Budapest
        #expect(data.contains("2026-03-05T11:00:00.000+01:00"))   // winter time in Budapest
        let manifest = String(decoding: files.manifest, as: UTF8.self)
        #expect(manifest.contains("2026-09-24T10:00:00.000+02:00"))

        let chicago = try #require(ArchiveDate.parse("2026-09-24T08:00:00-05:00"))
        let utc = try #require(ArchiveDate.parse("2026-09-24T13:00:00Z"))
        let compact = try #require(ArchiveDate.parse("2026-09-24T15:00:00.000+0200"))
        #expect(chicago == utc)
        #expect(compact == utc)
        let zone = try #require(TimeZone(identifier: "America/Chicago"))
        #expect(ArchiveDate.format(utc, timeZone: zone) == "2026-09-24T08:00:00.000-05:00")
        #expect(ArchiveDate.parse("24/09/2026") == nil)
    }

    @Test func lowercaseUUIDsAreAccepted() throws {
        let data = try ArchiveFixture.mutating(ArchiveFixture.data("data")) { root in
            if var products = root["products"] as? [[String: Any]] {
                products[0]["publicId"] = ArchiveSamples.milkID.uuidString.lowercased()
                root["products"] = products
            }
        }
        let contents = try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"), data: data)
        #expect(contents == ArchiveSamples.sampleV1)
        let encoded = String(decoding: try ArchiveCodec.encode(contents).data, as: UTF8.self)
        #expect(encoded.contains(ArchiveSamples.milkID.uuidString))
    }

    @Test func productLinkTravelsWithTheProduct() throws {
        let contents = try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"),
                                               data: ArchiveFixture.data("data"))
        let milk = try #require(contents.data.products.first { $0.publicId == ArchiveSamples.milkID })
        let flour = try #require(contents.data.products.first { $0.publicId == ArchiveSamples.flourID })
        #expect(milk.url == "https://www.mizo.hu/termekek/tej")
        #expect(flour.url == nil)
        let encoded = String(decoding: try ArchiveCodec.encode(contents).data, as: UTF8.self)
        #expect(!encoded.contains("isEatable"))
    }

    @Test func inventoryEventsKeepTheirHistory() throws {
        let contents = try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"),
                                               data: ArchiveFixture.data("data"))
        let events = contents.data.inventoryEvents
        #expect(events.map(\.kind) == [.added, .consumed, .added, .deleted])
        #expect(contents.manifest.counts.inventoryEvents == 4)

        let consumed = try #require(events.first { $0.publicId == ArchiveSamples.milkConsumedEventID })
        #expect(consumed.product == ArchiveSamples.milkID)
        #expect(consumed.inventoryItem == ArchiveSamples.milkItemID)
        #expect(consumed.quantity.value == Decimal(string: "0.5"))
        #expect(consumed.unit == .liter)
        #expect(consumed.fromLocationName == "Hűtő")
        #expect(consumed.toLocationName == nil)
        #expect(consumed.createdBy == "_member0002")

        // The stock item of a deleted event is gone; the event still belongs to the product.
        let deleted = try #require(events.first { $0.publicId == ArchiveSamples.milkDeletedEventID })
        #expect(deleted.inventoryItem == nil)
        #expect(deleted.product == ArchiveSamples.milkID)
    }

    @Test func unknownFutureFieldsAreIgnored() throws {
        let manifest = try ArchiveFixture.mutating(ArchiveFixture.data("manifest")) {
            $0["generator"] = "larari-web 2.0"
        }
        let data = try ArchiveFixture.mutating(ArchiveFixture.data("data")) { root in
            root["recipes"] = [["publicId": "F0000000-0000-4000-8000-000000000001"]]
            if var products = root["products"] as? [[String: Any]] {
                products[0]["nutrition"] = ["kcal": 64]
                root["products"] = products
            }
        }
        let contents = try ArchiveCodec.decode(manifest: manifest, data: data)
        #expect(contents == ArchiveSamples.sampleV1)
    }

    @Test func newerSchemaVersionIsRejected() throws {
        let manifest = try ArchiveFixture.mutating(ArchiveFixture.data("manifest")) {
            $0["schemaVersion"] = 2
            $0["counts"] = nil       // a v2 manifest may look different; the version check still wins
        }
        #expect(throws: ArchiveError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try ArchiveCodec.decodeManifest(manifest)
        }
        #expect(throws: ArchiveError.unsupportedSchemaVersion(found: 2, supported: 1)) {
            try ArchiveCodec.decode(manifest: manifest, data: ArchiveFixture.data("data"))
        }
    }

    @Test func zeroOrMissingSchemaVersionIsCorrupted() throws {
        let zero = try ArchiveFixture.mutating(ArchiveFixture.data("manifest")) { $0["schemaVersion"] = 0 }
        let missing = try ArchiveFixture.mutating(ArchiveFixture.data("manifest")) { $0["schemaVersion"] = nil }
        for manifest in [zero, missing, Data("not json".utf8)] {
            let error = #expect(throws: ArchiveError.self) { try ArchiveCodec.decodeManifest(manifest) }
            guard case .corrupted = error else {
                Issue.record("expected .corrupted, got \(String(describing: error))")
                continue
            }
        }
    }

    @Test func countMismatchIsRejected() throws {
        for key in ["products", "inventoryEvents"] {
            let manifest = try ArchiveFixture.mutating(ArchiveFixture.data("manifest")) { root in
                var counts = root["counts"] as? [String: Any] ?? [:]
                counts[key] = 5
                root["counts"] = counts
            }
            #expect(throws: ArchiveError.countMismatch) {
                try ArchiveCodec.decode(manifest: manifest, data: ArchiveFixture.data("data"))
            }
        }
    }

    @Test func invalidImageReferenceIsRejected() throws {
        let data = try ArchiveFixture.mutating(ArchiveFixture.data("data")) { root in
            if var products = root["products"] as? [[String: Any]] {
                products[0]["image"] = "../../etc/passwd"
                root["products"] = products
            }
        }
        #expect(throws: ArchiveError.invalidImageReference("../../etc/passwd")) {
            try ArchiveCodec.decode(manifest: ArchiveFixture.data("manifest"), data: data)
        }
        #expect(ArchiveCodec.isValidImageReference("images/" + String(repeating: "a", count: 64) + ".jpg"))
        #expect(!ArchiveCodec.isValidImageReference("images/" + String(repeating: "A", count: 64) + ".jpg"))
        #expect(!ArchiveCodec.isValidImageReference("images/abc.jpg"))
    }

    @Test func imageReferencesAreCountedOnce() {
        var data = ArchiveSamples.sampleV1.data
        let ref = "images/" + String(repeating: "b", count: 64) + ".jpg"
        data.products[0].image = ref
        data.products[1].image = ref
        data.members[0].avatar = ref
        #expect(data.imageReferences == [ref])
        #expect(data.counts.images == 1)
    }

    @Test func countsSubscriptCoversEveryEntity() {
        var counts = ArchiveCounts()
        for (index, entity) in ArchiveEntity.allCases.enumerated() {
            counts[entity] = index + 1
        }
        for (index, entity) in ArchiveEntity.allCases.enumerated() {
            #expect(counts[entity] == index + 1)
        }
        #expect(ArchiveEntity.allCases.firstIndex(of: .inventoryEvents)! > ArchiveEntity.allCases.firstIndex(of: .inventoryItems)!)
    }

    @Test func archiveErrorsHaveLocalizedDescriptions() {
        let errors: [ArchiveError] = [
            .unsupportedSchemaVersion(found: 2, supported: 1), .corrupted("x"), .countMismatch,
            .invalidImageReference("x"), .missingEntry("x"), .missingImage("x"),
            .imageChecksumMismatch("x"), .duplicatePublicId(UUID()),
            .brokenReference(entity: .products, publicId: UUID(), field: "product"), .unsavedChanges
        ]
        for error in errors {
            let description = error.errorDescription ?? ""
            #expect(!description.isEmpty)
            #expect(!description.hasPrefix("archive.error."), "Missing catalog entry for \(error)")
        }
    }
}

extension ArchiveCodecTests {
    /// The fixture is exactly what the encoder writes, so it doubles as the format reference.
    @Test func encodingMatchesTheFixtureByteForByte() throws {
        let files = try ArchiveCodec.encode(ArchiveSamples.sampleV1)
        let trailingNewline = Data("\n".utf8)
        #expect(files.manifest + trailingNewline == (try ArchiveFixture.data("manifest")))
        #expect(files.data + trailingNewline == (try ArchiveFixture.data("data")))
    }
}
