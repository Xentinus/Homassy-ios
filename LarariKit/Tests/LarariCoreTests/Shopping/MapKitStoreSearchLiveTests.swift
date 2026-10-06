import Foundation
import Testing
@testable import LarariCore

@Suite("MapKit store search (live)",
       .enabled(if: ProcessInfo.processInfo.environment["LARARI_NETWORK_TESTS"] == "1"))
struct MapKitStoreSearchLiveTests {
    let search = MapKitStoreSearch()
    let deak = StoreSamples.deak

    @Test func nearbyFindsShopsAroundDeakSquare() async throws {
        let results = try await search.nearby(latitude: deak.latitude, longitude: deak.longitude, radiusMeters: 1_000)
        #expect(!results.isEmpty)
        #expect(results.allSatisfy { !$0.mapItemIdentifier.isEmpty && !$0.name.isEmpty })
        let distances = results.map { $0.distance(toLatitude: deak.latitude, longitude: deak.longitude) }
        #expect(distances == distances.sorted())
        #expect(Set(results.map(\.mapItemIdentifier)).count == results.count)
    }

    @Test func searchByNameFindsASpar() async throws {
        let results = try await search.search(text: "Spar", latitude: deak.latitude, longitude: deak.longitude)
        #expect(results.contains { $0.name.localizedCaseInsensitiveContains("spar") })
    }

    @Test func blankTextSearchesNothing() async throws {
        #expect(try await search.search(text: "  ", latitude: deak.latitude, longitude: deak.longitude).isEmpty)
    }
}
