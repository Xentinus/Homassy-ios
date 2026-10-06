import Foundation
import MapKit
import Testing
@testable import LarariCore

@Suite("Store search")
struct StoreSearchTests {
    @Test func distanceIsHaversineInMetres() {
        let budapest = StoreResult(mapItemIdentifier: "a", name: "Budapest", latitude: 47.4979, longitude: 19.0402)
        let vienna = budapest.distance(toLatitude: 48.2082, longitude: 16.3738)
        #expect(vienna > 205_000 && vienna < 225_000)
        #expect(budapest.distance(toLatitude: 47.4979, longitude: 19.0402) < 0.001)
    }

    @Test func rankDeduplicatesAndSortsByDistance() {
        let duplicate = StoreResult(mapItemIdentifier: StoreSamples.lidlBuda.mapItemIdentifier, name: "Lidl (dup)",
                                    latitude: 0, longitude: 0)
        let ranked = MapKitStoreSearch.rank(
            [StoreSamples.lidlBuda, StoreSamples.aldiNyugati, duplicate, StoreSamples.sparAstoria],
            latitude: StoreSamples.deak.latitude, longitude: StoreSamples.deak.longitude)
        #expect(ranked.map(\.mapItemIdentifier) == ["I-SPAR-ASTORIA", "I-ALDI-NYUGATI", "I-LIDL-BUDA"])
        #expect(ranked.last?.name == "Lidl Buda")
    }

    @Test func filterUsesTheFourShopCategories() {
        #expect(MapKitStoreSearch.categories == [.foodMarket, .store, .bakery, .pharmacy])
    }

    @Test func identifiableByMapItemIdentifier() {
        #expect(StoreSamples.sparAstoria.id == "I-SPAR-ASTORIA")
    }

    @Test func fakeRecordsCalls() async throws {
        let fake = FakeStoreSearch(nearby: [StoreSamples.sparAstoria], search: ["aldi": [StoreSamples.aldiNyugati]])
        #expect(try await fake.nearby(latitude: 1, longitude: 2, radiusMeters: 500) == [StoreSamples.sparAstoria])
        #expect(try await fake.search(text: "aldi", latitude: 1, longitude: 2) == [StoreSamples.aldiNyugati])
        #expect(fake.calls == [.nearby(latitude: 1, longitude: 2, radius: 500),
                               .search(text: "aldi", latitude: 1, longitude: 2)])
    }
}
