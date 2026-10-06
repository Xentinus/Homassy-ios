import Foundation
import Testing
@testable import LarariCore

@MainActor
@Suite("Store labels and address cache")
struct StoreLabelTests {
    let hu = Locale(identifier: "hu_HU")
    let en = Locale(identifier: "en_US")

    @Test func addressSplitsStreetAndLocality() throws {
        let two = try #require(StoreAddress(short: " Sport u. 2–4., Budaörs "))
        #expect(two.short == "Sport u. 2–4., Budaörs")
        #expect(two.street == "Sport u. 2–4." && two.locality == "Budaörs")
        let three = try #require(StoreAddress(short: "Fehérvári út 95., XI. kerület, Budapest"))
        #expect(three.street == "Fehérvári út 95." && three.locality == "Budapest")
        let one = try #require(StoreAddress(short: "Budaörs"))
        #expect(one.street == nil && one.locality == nil)
        #expect(StoreAddress(short: "  ") == nil)
        #expect(StoreAddress(short: nil) == nil)
    }

    @Test func distanceIsMetresBelowAKilometre() {
        #expect(StoreLabel.distanceText(649.6, locale: en).hasPrefix("650"))
        #expect(StoreLabel.distanceText(649.6, locale: en).hasSuffix("m"))
        let km = StoreLabel.distanceText(1_234, locale: hu)
        #expect(km.contains("1,2") && km.hasSuffix("km"))
        #expect(StoreLabel.distanceText(1_234, locale: en).contains("1.2"))
    }

    @Test func distanceRoundsToAKilometreBeforeSwitchingUnits() {
        // 999.6 rounds to 1000, which must render as "1,0 km", not "1000 m".
        #expect(StoreLabel.distanceText(999.6, locale: hu).hasPrefix("1,0"))
        #expect(StoreLabel.distanceText(999.6, locale: hu).hasSuffix("km"))
        #expect(StoreLabel.distanceText(999.4, locale: en).hasSuffix("m"))
    }

    @Test func subtitleJoinsWhatIsKnown() throws {
        let address = try #require(StoreAddress(short: "Sport u. 2–4., Budaörs"))
        let both = try #require(StoreLabel.subtitle(address: address, distance: 1_200, locale: hu))
        #expect(both.hasSuffix(" · Sport u. 2–4., Budaörs") && both.contains("1,2"))
        #expect(StoreLabel.subtitle(address: address, distance: nil, locale: hu) == "Sport u. 2–4., Budaörs")
        #expect(StoreLabel.subtitle(address: nil, distance: 650, locale: en)?.hasSuffix("m") == true)
        #expect(StoreLabel.subtitle(address: nil, distance: nil, locale: hu) == nil)
    }

    @Test func compactNameUsesLocalityOrStreet() throws {
        let address = try #require(StoreAddress(short: "Sport u. 2–4., Budaörs"))
        #expect(StoreLabel.compact(name: "Auchan", address: address, useStreet: false) == "Auchan · Budaörs")
        #expect(StoreLabel.compact(name: "Auchan", address: address, useStreet: true) == "Auchan · Sport u. 2–4.")
        #expect(StoreLabel.compact(name: "Auchan", address: nil, useStreet: false) == "Auchan")
        #expect(StoreLabel.compact(name: "Piac", address: StoreAddress(short: "Budaörs"), useStreet: false) == "Piac")
    }

    @Test func cacheRoundTripsThroughAFile() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "store-addresses-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let address = try #require(StoreAddress(short: "Fő utca 1., Budapest"))
        let cache = StoreAddressCache(fileURL: url)
        #expect(cache.address(for: "I-1") == nil)
        cache.set(address, for: "I-1")
        #expect(cache.address(for: "I-1") == address)
        #expect(StoreAddressCache(fileURL: url).address(for: "I-1") == address)
    }

    @Test func theCategoryRoundTripsAndALegacyFileWithoutItDecodes() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "store-addresses-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        // A P2-08b file: no category field.
        try Data(#"{"I-1":{"short":"Fő utca 1., Budapest","street":"Fő utca 1.","locality":"Budapest"}}"#.utf8)
            .write(to: url)
        let legacy = try #require(StoreAddressCache(fileURL: url).address(for: "I-1"))
        #expect(legacy.short == "Fő utca 1., Budapest" && legacy.locality == "Budapest")
        #expect(legacy.category == nil)
        let cache = StoreAddressCache(fileURL: url)
        cache.set(try #require(StoreAddress(short: "Fő utca 1., Budapest", category: "MKPOICategoryBakery")), for: "I-1")
        #expect(StoreAddressCache(fileURL: url).address(for: "I-1")?.category == "MKPOICategoryBakery")
        #expect(StoreAddress(short: " ", category: "MKPOICategoryBakery") == nil)
    }

    @Test func aCorruptFileStartsEmptyAndMemoryOnlyWorks() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "store-addresses-\(UUID()).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("not json".utf8).write(to: url)
        #expect(StoreAddressCache(fileURL: url).address(for: "I-1") == nil)
        let memory = StoreAddressCache(fileURL: nil)
        memory.set(try #require(StoreAddress(short: "Fő utca 1., Budapest")), for: "I-2")
        #expect(memory.address(for: "I-2")?.locality == "Budapest")
    }
}
