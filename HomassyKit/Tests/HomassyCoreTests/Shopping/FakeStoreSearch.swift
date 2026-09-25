import Foundation
import Synchronization
@testable import HomassyCore

final class FakeStoreSearch: StoreSearching {
    enum Call: Equatable, Sendable {
        case nearby(latitude: Double, longitude: Double, radius: Double)
        case search(text: String, latitude: Double, longitude: Double)
    }
    struct Failure: Error {}

    let nearbyResults: [StoreResult]
    let searchResults: [String: [StoreResult]]
    let fails: Bool
    private let recorded = Mutex<[Call]>([])

    init(nearby: [StoreResult] = [], search: [String: [StoreResult]] = [:], fails: Bool = false) {
        nearbyResults = nearby
        searchResults = search
        self.fails = fails
    }

    var calls: [Call] { recorded.withLock { $0 } }

    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        recorded.withLock { $0.append(.nearby(latitude: latitude, longitude: longitude, radius: radiusMeters)) }
        if fails { throw Failure() }
        return nearbyResults
    }

    func search(text: String, latitude: Double, longitude: Double) async throws -> [StoreResult] {
        recorded.withLock { $0.append(.search(text: text, latitude: latitude, longitude: longitude)) }
        if fails { throw Failure() }
        return searchResults[text] ?? []
    }
}

@MainActor
final class FakeLocation: LocationAuthorizing {
    var access: LocationAccess
    var grantOnRequest: Bool
    var coordinate: Coordinate?
    private(set) var requests = 0

    init(access: LocationAccess = .notDetermined, grantOnRequest: Bool = true, coordinate: Coordinate? = nil) {
        self.access = access
        self.grantOnRequest = grantOnRequest
        self.coordinate = coordinate
    }

    func requestWhenInUse() async -> LocationAccess {
        requests += 1
        if access == .notDetermined { access = grantOnRequest ? .authorized : .denied }
        return access
    }

    func currentCoordinate() async -> Coordinate? {
        access == .authorized ? coordinate : nil
    }
}

enum StoreSamples {
    static let sparAstoria = StoreResult(mapItemIdentifier: "I-SPAR-ASTORIA", name: "Spar Astoria",
                                         latitude: 47.4935, longitude: 19.0602, subtitle: "Károly krt. 1")
    static let aldiNyugati = StoreResult(mapItemIdentifier: "I-ALDI-NYUGATI", name: "Aldi Nyugati",
                                         latitude: 47.5105, longitude: 19.0567, subtitle: "Teréz krt. 55")
    static let lidlBuda = StoreResult(mapItemIdentifier: "I-LIDL-BUDA", name: "Lidl Buda",
                                      latitude: 47.4812, longitude: 19.0205, subtitle: nil)
    static let deak = Coordinate(latitude: 47.4979, longitude: 19.0540)
}
