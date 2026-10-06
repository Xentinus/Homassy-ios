import CoreData
import Foundation
import Testing
import ZIPFoundation
@testable import LarariCore

@MainActor
@Suite("Archive exporter")
struct ArchiveExporterTests {
    let stack: ArchiveTestStack
    let budapest: TimeZone
    let fixedNow: Date

    init() throws {
        stack = try ArchiveTestStack()
        budapest = try #require(TimeZone(identifier: "Europe/Budapest"))
        fixedNow = ArchiveTestStack.date("2026-09-24T08:00:00Z")
    }

    private func exporter() -> ArchiveExporter {
        ArchiveExporter(context: stack.context, appVersion: "1.0 (7)",
                        locale: Locale(identifier: "hu_HU"), timeZone: budapest, now: { [fixedNow] in fixedNow })
    }

    private func unzip(_ url: URL) throws -> URL {
        let destination = FileManager.default.temporaryDirectory.appending(path: "unzipped-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        try FileManager.default.unzipItem(at: url, to: destination)
        return destination
    }

    @Test func exportWritesANamedZipWithManifestDataAndImages() throws {
        try stack.seedHousehold()
        let seeded = try #require(try stack.fetch(Space.self, "name == %@", "Otthon").first)
        let url = try exporter().export(space: seeded)

        #expect(url.lastPathComponent == "Otthon-2026-09-24.larari")
        let folder = try unzip(url)
        let manifestURL = folder.appending(path: "manifest.json")
        let dataURL = folder.appending(path: "data.json")
        #expect(FileManager.default.fileExists(atPath: manifestURL.path))
        #expect(FileManager.default.fileExists(atPath: dataURL.path))

        let contents = try ArchiveCodec.decode(manifest: Data(contentsOf: manifestURL), data: Data(contentsOf: dataURL))
        #expect(contents.manifest.schemaVersion == 1)
        #expect(contents.manifest.appVersion == "1.0 (7)")
        #expect(contents.manifest.locale == "hu-HU")
        #expect(contents.manifest.timeZone == "Europe/Budapest")
        #expect(contents.manifest.spaceName == "Otthon")
        #expect(contents.manifest.spaceKind == .household)
        #expect(contents.manifest.exportedAt == fixedNow)
        let manifestText = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(manifestText.contains("2026-09-24T10:00:00.000+02:00"))
    }

    @Test func countsMatchTheSpace() throws {
        let seeded = try stack.seedHousehold()
        let loaded = try exporter().snapshot(of: seeded.space)
        var expected = ArchiveCounts()
        expected.members = 2
        expected.products = 4
        expected.storageLocations = 1
        expected.shoppingLocations = 1
        expected.shoppingLists = 1
        expected.inventoryItems = 2
        expected.consumptionLogs = 1
        expected.inventoryEvents = 2
        expected.shoppingListItems = 2
        expected.images = 2
        #expect(loaded.contents.manifest.counts == expected)
        #expect(loaded.contents.data.counts == expected)
    }

    @Test func identicalImagesAreStoredOnce() throws {
        let seeded = try stack.seedHousehold()
        let url = try exporter().export(space: seeded.space)
        let folder = try unzip(url)
        let files = try FileManager.default.contentsOfDirectory(atPath: folder.appending(path: "images").path).sorted()
        let sharedRef = ArchiveImages.reference(for: seeded.sharedPhoto)
        let flourRef = ArchiveImages.reference(for: seeded.flourPhoto)
        #expect(files == [sharedRef, flourRef].map { String($0.dropFirst("images/".count)) }.sorted())

        let data = try ArchivePackage.read(url).contents.data
        let byName = Dictionary(uniqueKeysWithValues: data.products.map { ($0.name, $0) })
        #expect(byName["Tej"]?.image == sharedRef)
        #expect(byName["Kefir"]?.image == sharedRef)
        #expect(byName["Liszt"]?.image == flourRef)
        #expect(byName["Só"]?.image == nil)
        let bytes = try Data(contentsOf: folder.appending(path: sharedRef))
        #expect(bytes == seeded.sharedPhoto)
    }

    @Test func onlyTheExportedSpaceIsIncluded() throws {
        let seeded = try stack.seedHousehold()
        let other = stack.makeSpace(name: "Nyaraló")
        let foreign: Product = stack.insert(Product.self, in: other)
        foreign.space = other
        foreign.name = "Idegen"
        foreign.image = Data(repeating: 0xEF, count: 512)
        let foreignEvent: InventoryEvent = stack.insert(InventoryEvent.self, in: other)
        foreignEvent.product = foreign
        foreignEvent.kind = .added
        try stack.context.save()

        let loaded = try exporter().snapshot(of: seeded.space)
        #expect(loaded.images.count == 2)
        #expect(loaded.images[ArchiveImages.reference(for: Data(repeating: 0xEF, count: 512))] == nil)
        #expect(!loaded.contents.data.products.contains { $0.name == "Idegen" })
        #expect(!loaded.contents.data.inventoryEvents.contains { $0.publicId == foreignEvent.publicId })
    }

    @Test func membersAreExportedWithoutShareMetadata() throws {
        let seeded = try stack.seedHousehold()
        let url = try exporter().export(space: seeded.space)
        let folder = try unzip(url)
        let json = try Data(contentsOf: folder.appending(path: "data.json"))

        let root = try #require(try JSONSerialization.jsonObject(with: json) as? [String: Any])
        let members = try #require(root["members"] as? [[String: Any]])
        #expect(members.count == 2)
        #expect(Set(members.flatMap(\.keys)) == ["publicId", "createdAt", "updatedAt", "createdBy", "updatedBy",
                                                 "userRecordName", "displayName", "colorSeed"])
        #expect(Set(members.compactMap { $0["displayName"] as? String }) == ["Béla", "Anna"])
        #expect(Set(members.compactMap { $0["colorSeed"] as? String }) == ["_owner", "_anna"])
        let text = String(decoding: json, as: UTF8.self)
        #expect(!text.localizedCaseInsensitiveContains("share"))
        #expect(!text.localizedCaseInsensitiveContains("participant"))
        #expect(!text.localizedCaseInsensitiveContains("permission"))
    }

    @Test func relationshipsAreExportedAsPublicIds() throws {
        let seeded = try stack.seedHousehold()
        let data = try exporter().snapshot(of: seeded.space).contents.data
        let milkItem = try #require(data.inventoryItems.first { $0.publicId == seeded.milkItem.publicId })
        #expect(milkItem.product == seeded.milk.publicId)
        #expect(milkItem.storageLocation == seeded.fridge.publicId)
        #expect(milkItem.shoppingLocation == seeded.spar.publicId)
        #expect(milkItem.quantity.value == ArchiveTestStack.decimal("1.5"))
        #expect(milkItem.price?.value == ArchiveTestStack.decimal("459"))
        #expect(data.consumptionLogs.first?.inventoryItem == seeded.milkItem.publicId)
        let bread = try #require(data.shoppingListItems.first { $0.publicId == seeded.breadListItem.publicId })
        #expect(bread.list == seeded.weekly.publicId)
        #expect(bread.product == nil)
        #expect(bread.customName == "Kenyér")
        #expect(data.space.publicId == seeded.space.publicId)
    }

    @Test func productLinkIsExported() throws {
        let seeded = try stack.seedHousehold()
        let products = try exporter().snapshot(of: seeded.space).contents.data.products
        #expect(products.first { $0.publicId == seeded.milk.publicId }?.url == "https://www.mizo.hu/termekek/tej")
        #expect(products.first { $0.publicId == seeded.flour.publicId }?.url == nil)
    }

    @Test func inventoryEventsAreExportedWithTheirHistory() throws {
        let seeded = try stack.seedHousehold()
        let events = try exporter().snapshot(of: seeded.space).contents.data.inventoryEvents
        #expect(events.map(\.publicId.uuidString) == events.map(\.publicId.uuidString).sorted())

        let added = try #require(events.first { $0.publicId == seeded.milkAddedEvent.publicId })
        #expect(added.product == seeded.milk.publicId)
        #expect(added.inventoryItem == seeded.milkItem.publicId)
        #expect(added.kind == .added)
        #expect(added.quantity.value == 2)
        #expect(added.unit == .liter)
        #expect(added.toLocationName == "Hűtő")
        #expect(added.fromLocationName == nil)
        #expect(added.occurredAt == ArchiveTestStack.date("2026-09-01T12:00:00+02:00"))
        #expect(added.createdBy == stack.user)

        let deleted = try #require(events.first { $0.publicId == seeded.milkDeletedEvent.publicId })
        #expect(deleted.kind == .deleted)
        #expect(deleted.inventoryItem == nil)
        #expect(deleted.fromLocationName == "Hűtő")
    }

    @Test func outputIsDeterministicAndSortedByPublicId() throws {
        let seeded = try stack.seedHousehold()
        let first = try ArchivePackage.read(try exporter().export(space: seeded.space))
        let second = try ArchivePackage.read(try exporter().export(space: seeded.space))
        #expect(try ArchiveCodec.encode(first.contents).data == ArchiveCodec.encode(second.contents).data)
        let ids = first.contents.data.products.map(\.publicId.uuidString)
        #expect(ids == ids.sorted())
    }

    @Test func serviceContainerExposesTheArchiveServices() throws {
        let services = ServiceContainer(spaceStore: stack.spaceStore, context: stack.context,
                                        userRecordName: stack.user, persistence: stack.persistence)
        let archive = try #require(services.archive)
        let seeded = try stack.seedHousehold()
        #expect(try archive.makeExporter().snapshot(of: seeded.space).contents.data.space.publicId == seeded.space.publicId)
        #expect(ServiceContainer(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user).archive == nil)
    }

    @Test func fileNameIsSanitised() {
        let date = ArchiveTestStack.date("2026-09-24T23:30:00+02:00")
        #expect(ArchiveExporter.fileName(spaceName: "Otthon", date: date, timeZone: budapest)
                == "Otthon-2026-09-24.larari")
        #expect(ArchiveExporter.fileName(spaceName: "Lak/ás: 2", date: date, timeZone: budapest)
                == "Lak-ás- 2-2026-09-24.larari")
        #expect(ArchiveExporter.fileName(spaceName: "  ", date: date, timeZone: budapest)
                == "Larari-2026-09-24.larari")
    }
}
