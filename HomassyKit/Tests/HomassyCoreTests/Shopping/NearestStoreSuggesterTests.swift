import Foundation
import Testing
@testable import HomassyCore

@MainActor
@Suite("Nearest store suggester")
struct NearestStoreSuggesterTests {
    let stack: ShoppingTestStack
    let locations: ShoppingLocationService
    /// About 100 m north of Deák tér, and about 20 m.
    static let hundredMetres = StoreResult(mapItemIdentifier: "I-NEAR-100", name: "Spar Deák", latitude: 47.4988,
                                           longitude: 19.0540)
    static let twentyMetres = StoreResult(mapItemIdentifier: "I-NEAR-20", name: "Kisbolt", latitude: 47.49808,
                                          longitude: 19.0540)
    static let fiftyMetres = StoreResult(mapItemIdentifier: "I-NEAR-50", name: "Aldi Deák", latitude: 47.49835,
                                         longitude: 19.0540)

    init() throws {
        stack = try ShoppingTestStack()
        locations = ShoppingLocationService(spaceStore: stack.spaceStore, context: stack.context, userRecordName: stack.user)
    }

    private func suggester(_ search: FakeStoreSearch, access: LocationAccess = .authorized,
                           coordinate: Coordinate? = StoreSamples.deak) -> NearestStoreSuggester {
        NearestStoreSuggester(search: search, locations: locations,
                              location: FakeLocation(access: access, coordinate: coordinate))
    }

    @Test func withoutPermissionThereIsNoSuggestion() async {
        let search = FakeStoreSearch(nearby: [Self.twentyMetres])
        #expect(await suggester(search, access: .denied).suggestion(in: stack.space) == nil)
        #expect(await suggester(search, access: .notDetermined).suggestion(in: stack.space) == nil)
        #expect(search.calls.isEmpty)
    }

    @Test func savedStoreWithinRadiusWins() async throws {
        let saved = try locations.upsert(Self.hundredMetres, in: stack.space)
        let search = FakeStoreSearch(nearby: [Self.twentyMetres])
        let suggestion = try #require(await suggester(search).suggestion(in: stack.space))
        guard case .saved(let id, let name, let distance) = suggestion else {
            Issue.record("expected a saved store, got \(suggestion)")
            return
        }
        #expect(id == saved.publicId)
        #expect(name == "Spar Deák")
        #expect(distance > 90 && distance < 110)
        #expect(suggestion.name == "Spar Deák")
    }

    @Test func nearestSavedStoreWinsAmongSaved() async throws {
        try locations.upsert(Self.hundredMetres, in: stack.space)
        let closer = try locations.upsert(Self.fiftyMetres, in: stack.space)
        try locations.upsert(StoreSamples.lidlBuda, in: stack.space)       // kilometres away
        let suggestion = await suggester(FakeStoreSearch()).suggestion(in: stack.space)
        guard case .saved(let id, _, _) = suggestion else {
            Issue.record("expected a saved store")
            return
        }
        #expect(id == closer.publicId)
    }

    @Test func otherwiseTheNearestPlace() async throws {
        try locations.upsert(StoreSamples.lidlBuda, in: stack.space)       // saved, but too far
        let search = FakeStoreSearch(nearby: [Self.hundredMetres, Self.twentyMetres])
        let suggestion = try #require(await suggester(search).suggestion(in: stack.space))
        guard case .place(let result, let distance) = suggestion else {
            Issue.record("expected a place")
            return
        }
        #expect(result == Self.twentyMetres)
        #expect(distance < 30)
        #expect(search.calls == [.nearby(latitude: StoreSamples.deak.latitude, longitude: StoreSamples.deak.longitude,
                                         radius: NearestStoreSuggester.radiusMeters)])
    }

    @Test func nothingWithinTheRadius() async {
        let search = FakeStoreSearch(nearby: [StoreSamples.lidlBuda])
        #expect(await suggester(search).suggestion(in: stack.space) == nil)
    }

    @Test func noPositionOrFailureGivesNil() async {
        #expect(await suggester(FakeStoreSearch(nearby: [Self.twentyMetres]), coordinate: nil)
            .suggestion(in: stack.space) == nil)
        #expect(await suggester(FakeStoreSearch(fails: true)).suggestion(in: stack.space) == nil)
    }
}
