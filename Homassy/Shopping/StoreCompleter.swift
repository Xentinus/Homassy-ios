import HomassyCore
import MapKit
import Observation

/// As-you-type store names for the search field, from Apple Maps.
@MainActor
@Observable
final class StoreCompleter: NSObject, MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [String] = []
    @ObservationIgnored private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = .pointOfInterest
        completer.pointOfInterestFilter = MKPointOfInterestFilter(including: MapKitStoreSearch.categories)
    }

    func update(query: String, center: Coordinate?) {
        if let center {
            completer.region = MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: center.latitude, longitude: center.longitude),
                latitudinalMeters: MapKitStoreSearch.searchRadiusMeters,
                longitudinalMeters: MapKitStoreSearch.searchRadiusMeters)
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            completer.cancel()
            suggestions = []
        } else {
            completer.queryFragment = trimmed
        }
    }

    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        let titles = completer.results.map(\.title)
        MainActor.assumeIsolated {
            var seen = Set<String>()
            self.suggestions = Array(titles.filter { seen.insert($0).inserted }.prefix(6))
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        MainActor.assumeIsolated { self.suggestions = [] }
    }
}
