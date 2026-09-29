import Foundation
import Synchronization
@testable import HomassyCore

final class FakeStoreSearch: StoreSearching {
    enum Call: Equatable, Sendable {
        case nearby(latitude: Double, longitude: Double, radius: Double)
        case search(text: String, latitude: Double, longitude: Double)
        case places(text: String)
        case around(latitude: Double, longitude: Double, radius: Double)
    }
    struct Failure: Error {}

    let nearbyResults: [StoreResult]
    let searchResults: [String: [StoreResult]]
    let placeResults: [String: [PlaceResult]]
    let aroundResults: [StoreResult]
    let fails: Bool
    private let recorded = Mutex<[Call]>([])

    init(nearby: [StoreResult] = [], search: [String: [StoreResult]] = [:], places: [String: [PlaceResult]] = [:],
         around: [StoreResult] = [], fails: Bool = false) {
        nearbyResults = nearby
        searchResults = search
        placeResults = places
        aroundResults = around
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

    func places(text: String, latitude: Double, longitude: Double) async throws -> [PlaceResult] {
        recorded.withLock { $0.append(.places(text: text)) }
        if fails { throw Failure() }
        return placeResults[text] ?? []
    }

    func around(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        recorded.withLock { $0.append(.around(latitude: latitude, longitude: longitude, radius: radiusMeters)) }
        if fails { throw Failure() }
        return aroundResults
    }
}

/// Wraps `FakeStoreSearch` and holds chosen calls until the test releases them, so searches can overlap
/// and finish in any order (P2-08c final review).
final class SuspendingStoreSearch: StoreSearching {
    enum Gate: Hashable, Sendable {
        case search(String), places(String), around
    }
    private struct State {
        var held: Set<Gate>
        var waiting: [Gate: [CheckedContinuation<Void, Never>]] = [:]
    }

    let base: FakeStoreSearch
    private let state: Mutex<State>

    init(_ base: FakeStoreSearch, holding gates: Set<Gate>) {
        self.base = base
        state = Mutex(State(held: gates))
    }

    var calls: [FakeStoreSearch.Call] { base.calls }

    /// Lets every held and future call through `gate`.
    func release(_ gate: Gate) {
        let waiting = state.withLock { state in
            state.held.remove(gate)
            return state.waiting.removeValue(forKey: gate) ?? []
        }
        waiting.forEach { $0.resume() }
    }

    /// Waits (a bounded number of short sleeps) until a call is held at `gate`.
    func waitUntilHeld(_ gate: Gate) async -> Bool {
        for _ in 0..<2_000 {
            if state.withLock({ !($0.waiting[gate] ?? []).isEmpty }) { return true }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return false
    }

    private func pass(_ gate: Gate) async {
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let goesThrough = state.withLock { state in
                guard state.held.contains(gate) else { return true }
                state.waiting[gate, default: []].append(continuation)
                return false
            }
            if goesThrough { continuation.resume() }
        }
    }

    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        try await base.nearby(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }

    func search(text: String, latitude: Double, longitude: Double) async throws -> [StoreResult] {
        await pass(.search(text))
        return try await base.search(text: text, latitude: latitude, longitude: longitude)
    }

    func places(text: String, latitude: Double, longitude: Double) async throws -> [PlaceResult] {
        await pass(.places(text))
        return try await base.places(text: text, latitude: latitude, longitude: longitude)
    }

    func around(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        await pass(.around)
        return try await base.around(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }
}

@MainActor
final class FakeLocation: LocationAuthorizing {
    var access: LocationAccess
    var grantOnRequest: Bool
    var coordinate: Coordinate?
    var lastKnown: Coordinate?
    private(set) var requests = 0
    /// How often a live position was asked for (N-01: a background refresh never does).
    private(set) var liveRequests = 0

    init(access: LocationAccess = .notDetermined, grantOnRequest: Bool = true, coordinate: Coordinate? = nil,
         lastKnown: Coordinate? = nil) {
        self.access = access
        self.grantOnRequest = grantOnRequest
        self.coordinate = coordinate
        self.lastKnown = lastKnown
    }

    func requestWhenInUse() async -> LocationAccess {
        requests += 1
        if access == .notDetermined { access = grantOnRequest ? .authorized : .denied }
        return access
    }

    func currentCoordinate() async -> Coordinate? {
        liveRequests += 1
        return access == .authorized ? coordinate : nil
    }

    var lastKnownCoordinate: Coordinate? { access == .authorized ? lastKnown : nil }
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
