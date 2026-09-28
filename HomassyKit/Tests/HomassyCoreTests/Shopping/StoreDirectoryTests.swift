import CoreData
import Foundation
import Observation
import Synchronization
import Testing
@testable import HomassyCore

@MainActor
final class FakeAddressResolver: StoreAddressResolving {
    var answers: [String: String]
    var categories: [String: String]
    private(set) var calls: [String] = []
    init(_ answers: [String: String] = [:], categories: [String: String] = [:]) {
        self.answers = answers
        self.categories = categories
    }
    func details(forMapItem identifier: String) async -> StoreLookup? {
        calls.append(identifier)
        let short = answers[identifier], category = categories[identifier]
        guard short != nil || category != nil else { return nil }
        return StoreLookup(shortAddress: short, category: category)
    }
}

@MainActor
@Suite("Store directory")
struct StoreDirectoryTests {
    let stack: ShoppingTestStack
    let hu = Locale(identifier: "hu_HU")
    init() throws { stack = try ShoppingTestStack() }

    private func directory(_ resolver: FakeAddressResolver? = nil, location: FakeLocation? = nil,
                           cache: StoreAddressCache = StoreAddressCache(fileURL: nil)) -> StoreDirectory {
        StoreDirectory(context: stack.context, cache: cache, resolver: resolver, location: location, locale: hu)
    }

    private func store(_ name: String, _ identifier: String, lat: Double = 47.46, lon: Double = 18.95) throws -> ShoppingLocation {
        let store = try stack.makeStore(name, identifier: identifier)
        store.latitude = lat
        store.longitude = lon
        try stack.context.save()
        return store
    }

    @Test func aMissingAddressIsLookedUpOnce() async throws {
        let auchan = try store("Auchan", "I-AUCHAN")
        let resolver = FakeAddressResolver(["I-AUCHAN": "Sport u. 2–4., Budaörs"])
        let directory = directory(resolver)
        #expect(directory.address(of: auchan) == nil)
        _ = directory.address(of: auchan)
        for task in directory.lookups { await task.value }
        #expect(resolver.calls == ["I-AUCHAN"])
        #expect(directory.address(ofStore: auchan.publicId)?.locality == "Budaörs")
        #expect(directory.subtitle(ofStore: auchan.publicId) == "Sport u. 2–4., Budaörs")
        #expect(directory.compactName(ofStore: auchan.publicId) == "Auchan · Budaörs")
    }

    @Test func aFailedLookupIsNotRetriedAndNothingIsShown() async throws {
        let spar = try store("Spar", "I-SPAR")
        let resolver = FakeAddressResolver()
        let directory = directory(resolver)
        _ = directory.subtitle(ofStore: spar.publicId)
        for task in directory.lookups { await task.value }
        _ = directory.subtitle(ofStore: spar.publicId)
        #expect(resolver.calls == ["I-SPAR"])
        #expect(directory.subtitle(ofStore: spar.publicId) == nil)
        #expect(directory.compactName(ofStore: spar.publicId) == "Spar")
    }

    @Test func rememberCachesAPickedPlace() throws {
        let directory = directory()
        directory.remember(StoreResult(mapItemIdentifier: "I-NEW", name: "Új", latitude: 47.5, longitude: 19.0,
                                       subtitle: "Fő utca 1., Budapest"))
        directory.remember(StoreResult(mapItemIdentifier: "I-NONE", name: "Nincs", latitude: 47.5, longitude: 19.0))
        let new = try store("Új", "I-NEW")
        #expect(directory.subtitle(ofStore: new.publicId) == "Fő utca 1., Budapest")
        #expect(directory.address(of: try store("Nincs", "I-NONE")) == nil)
    }

    @Test func rememberStoresTheCategory() throws {
        let directory = directory()
        directory.remember(StoreResult(mapItemIdentifier: "I-NEW", name: "Új", latitude: 47.5, longitude: 19.0,
                                       subtitle: "Fő utca 1., Budapest", category: "MKPOICategoryFoodMarket"))
        let new = try store("Új", "I-NEW")
        #expect(directory.category(ofStore: new.publicId) == "MKPOICategoryFoodMarket")
        #expect(directory.address(ofStore: new.publicId)?.short == "Fő utca 1., Budapest")
    }

    @Test func categoryAndSubtitleComeFromOneCall() throws {
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs", category: "MKPOICategoryFoodMarket")),
                  for: "I-AUCHAN")
        let auchan = try store("Auchan", "I-AUCHAN")
        let directory = directory(cache: cache)
        let both = directory.categoryAndSubtitle(ofStore: auchan.publicId)
        #expect(both.category == "MKPOICategoryFoodMarket")
        #expect(both.subtitle == "Sport u. 2–4., Budaörs")
        #expect(both.subtitle == directory.subtitle(ofStore: auchan.publicId))
        let missing = directory.categoryAndSubtitle(ofStore: UUID())
        #expect(missing.category == nil && missing.subtitle == nil)
    }

    @Test func aLookupFillsTheCategory() async throws {
        let auchan = try store("Auchan", "I-AUCHAN")
        let resolver = FakeAddressResolver(["I-AUCHAN": "Sport u. 2–4., Budaörs"],
                                           categories: ["I-AUCHAN": "MKPOICategoryFoodMarket"])
        let directory = directory(resolver)
        #expect(directory.category(ofStore: auchan.publicId) == nil)
        for task in directory.lookups { await task.value }
        #expect(directory.category(ofStore: auchan.publicId) == "MKPOICategoryFoodMarket")
        #expect(directory.address(ofStore: auchan.publicId)?.short == "Sport u. 2–4., Budaörs")
        #expect(resolver.calls == ["I-AUCHAN"])
    }

    @Test func aCachedAddressWithoutACategoryIsBackfilledOnce() async throws {
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs")), for: "I-AUCHAN")
        let auchan = try store("Auchan", "I-AUCHAN")
        let resolver = FakeAddressResolver(categories: ["I-AUCHAN": "MKPOICategoryFoodMarket"])
        let directory = directory(resolver, cache: cache)
        #expect(directory.address(ofStore: auchan.publicId)?.short == "Sport u. 2–4., Budaörs",
                "the cached address shows while the category is looked up")
        _ = directory.category(ofStore: auchan.publicId)
        for task in directory.lookups { await task.value }
        #expect(directory.category(ofStore: auchan.publicId) == "MKPOICategoryFoodMarket")
        #expect(directory.address(ofStore: auchan.publicId)?.short == "Sport u. 2–4., Budaörs",
                "a lookup without an address keeps the cached one")
        #expect(resolver.calls == ["I-AUCHAN"], "one backfill lookup per run, not two")
    }

    @Test func aFailedBackfillIsNotRetried() async throws {
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs")), for: "I-AUCHAN")
        let auchan = try store("Auchan", "I-AUCHAN")
        let resolver = FakeAddressResolver()
        let directory = directory(resolver, cache: cache)
        _ = directory.category(ofStore: auchan.publicId)
        for task in directory.lookups { await task.value }
        _ = directory.category(ofStore: auchan.publicId)
        _ = directory.subtitle(ofStore: auchan.publicId)
        #expect(resolver.calls == ["I-AUCHAN"])
        #expect(directory.category(ofStore: auchan.publicId) == nil)
        #expect(directory.subtitle(ofStore: auchan.publicId) == "Sport u. 2–4., Budaörs")
    }

    @Test func distanceOnlyWhileAuthorized() async throws {
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs")), for: "I-AUCHAN")
        let auchan = try store("Auchan", "I-AUCHAN", lat: 47.4600, lon: 18.9500)
        let here = Coordinate(latitude: 47.4600, longitude: 18.9660)   // about 1,2 km east
        let denied = directory(location: FakeLocation(access: .denied, coordinate: here), cache: cache)
        await denied.refreshLocation()
        #expect(denied.subtitle(ofStore: auchan.publicId) == "Sport u. 2–4., Budaörs")
        let allowed = directory(location: FakeLocation(access: .authorized, coordinate: here), cache: cache)
        await allowed.refreshLocation()
        let subtitle = try #require(allowed.subtitle(ofStore: auchan.publicId))
        #expect(subtitle.contains("1,2") && subtitle.hasSuffix(" · Sport u. 2–4., Budaörs"))
    }

    @Test func sameNameSameLocalityShowsTheStreet() throws {
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs")), for: "I-A1")
        cache.set(try #require(StoreAddress(short: "Kossuth u. 5., Budaörs")), for: "I-A2")
        cache.set(try #require(StoreAddress(short: "Fehérvári út 95., Budapest")), for: "I-A3")
        let first = try store("Auchan", "I-A1")
        _ = try store("auchan", "I-A2")
        let third = try store("Auchan", "I-A3")
        let directory = directory(cache: cache)
        #expect(directory.compactName(ofStore: first.publicId) == "Auchan · Sport u. 2–4.")
        #expect(directory.compactName(ofStore: third.publicId) == "Auchan · Budapest")
        #expect(directory.compactName(ofStore: UUID()) == nil)
        #expect(directory.compactName(ofStore: nil) == nil)
    }

    @Test func twinLocalityArrivesThroughTheResolverToo() async throws {
        // The twin's own address is not cached yet; it only arrives through the fake resolver.
        let cache = StoreAddressCache(fileURL: nil)
        cache.set(try #require(StoreAddress(short: "Sport u. 2–4., Budaörs")), for: "I-A1")
        let resolver = FakeAddressResolver(["I-A2": "Kossuth u. 5., Budaörs"])
        let first = try store("Auchan", "I-A1")
        _ = try store("auchan", "I-A2")
        let directory = directory(resolver, cache: cache)
        #expect(directory.compactName(ofStore: first.publicId) == "Auchan · Budaörs", "the twin's locality is not known yet")
        for task in directory.lookups { await task.value }
        #expect(directory.compactName(ofStore: first.publicId) == "Auchan · Sport u. 2–4.",
                "the twin's locality arrived through the resolver, so the street disambiguates now")
    }

    @Test func refreshLocationDoesNotInvalidateWhenTheCoordinateIsUnchanged() async throws {
        let here = Coordinate(latitude: 47.4600, longitude: 18.9660)
        let location = FakeLocation(access: .authorized, coordinate: here)
        let directory = directory(location: location)
        await directory.refreshLocation()
        #expect(directory.coordinate == here)
        let changed = Mutex(false)
        withObservationTracking { _ = directory.coordinate } onChange: { changed.withLock { $0 = true } }
        await directory.refreshLocation()
        #expect(!(changed.withLock { $0 }), "the same coordinate must not re-trigger observers")
    }

    @Test func upsertReportsThePick() throws {
        let locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user)
        var reported: [String] = []
        locations.onUpsert = { reported.append($0.mapItemIdentifier) }
        try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        try locations.upsert(StoreSamples.sparAstoria, in: stack.space)
        #expect(reported == ["I-SPAR-ASTORIA", "I-SPAR-ASTORIA"])
    }
}
