import Foundation
import MapKit

public struct MapKitStoreSearch: StoreSearching {
    public static var categories: [MKPointOfInterestCategory] { [.foodMarket, .store, .bakery, .pharmacy] }
    public static let searchRadiusMeters: Double = 30_000

    public init() {}

    public func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        try await Self.runNearby(latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }

    public func search(text: String, latitude: Double, longitude: Double) async throws -> [StoreResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return try await Self.runSearch(query: query, latitude: latitude, longitude: longitude)
    }

    /// Region for address searches: wide, so a town or a street across the country is found too.
    public static let placeSearchRadiusMeters: Double = 200_000

    public func places(text: String, latitude: Double, longitude: Double) async throws -> [PlaceResult] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return [] }
        return try await Self.runPlaces(query: query, latitude: latitude, longitude: longitude)
    }

    public static func rank(_ results: [StoreResult], latitude: Double, longitude: Double) -> [StoreResult] {
        var seen = Set<String>()
        return results
            .filter { seen.insert($0.mapItemIdentifier).inserted }
            .sorted {
                $0.distance(toLatitude: latitude, longitude: longitude)
                    < $1.distance(toLatitude: latitude, longitude: longitude)
            }
    }

    @MainActor
    private static func runNearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult] {
        let center = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let request = MKLocalPointsOfInterestRequest(center: center, radius: radiusMeters)
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        let response = try await MKLocalSearch(request: request).start()
        return rank(response.mapItems.compactMap(StoreResult.init(mapItem:)), latitude: latitude, longitude: longitude)
    }

    @MainActor
    private static func runSearch(query: String, latitude: Double, longitude: Double) async throws -> [StoreResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .pointOfInterest
        request.pointOfInterestFilter = MKPointOfInterestFilter(including: categories)
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                            latitudinalMeters: searchRadiusMeters,
                                            longitudinalMeters: searchRadiusMeters)
        let response = try await MKLocalSearch(request: request).start()
        return rank(response.mapItems.compactMap(StoreResult.init(mapItem:)), latitude: latitude, longitude: longitude)
    }
}

extension MapKitStoreSearch {
    @MainActor
    private static func runPlaces(query: String, latitude: Double, longitude: Double) async throws -> [PlaceResult] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = .address
        request.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                                            latitudinalMeters: placeSearchRadiusMeters,
                                            longitudinalMeters: placeSearchRadiusMeters)
        let response = try await MKLocalSearch(request: request).start()
        var seen = Set<String>()
        return response.mapItems.compactMap { item -> PlaceResult? in
            let coordinate = item.location.coordinate
            let title = item.name ?? item.address?.shortAddress ?? ""
            guard !title.isEmpty else { return nil }
            let id = item.identifier?.rawValue ?? "\(coordinate.latitude),\(coordinate.longitude)"
            guard seen.insert(id).inserted else { return nil }
            let subtitle = item.address?.fullAddress
            return PlaceResult(id: id, title: title, subtitle: subtitle == title ? nil : subtitle,
                               coordinate: Coordinate(latitude: coordinate.latitude, longitude: coordinate.longitude))
        }
    }
}

extension StoreResult {
    /// Map items without a stable identifier cannot be stored and are skipped.
    @MainActor
    public init?(mapItem: MKMapItem) {
        guard let identifier = mapItem.identifier?.rawValue, let name = mapItem.name, !name.isEmpty else { return nil }
        let coordinate = mapItem.location.coordinate
        self.init(mapItemIdentifier: identifier, name: name, latitude: coordinate.latitude,
                  longitude: coordinate.longitude, subtitle: mapItem.address?.shortAddress)
    }
}
