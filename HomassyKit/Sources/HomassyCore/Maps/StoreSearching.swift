import Foundation

public struct StoreResult: Sendable, Equatable, Hashable, Identifiable {
    public var mapItemIdentifier: String
    public var name: String
    public var latitude: Double
    public var longitude: Double
    public var subtitle: String?

    public var id: String { mapItemIdentifier }

    public init(mapItemIdentifier: String, name: String, latitude: Double, longitude: Double, subtitle: String? = nil) {
        self.mapItemIdentifier = mapItemIdentifier
        self.name = name
        self.latitude = latitude
        self.longitude = longitude
        self.subtitle = subtitle
    }

    /// Great-circle distance in metres (haversine, mean Earth radius).
    public func distance(toLatitude otherLatitude: Double, longitude otherLongitude: Double) -> Double {
        let radius = 6_371_008.8
        let φ1 = latitude * .pi / 180
        let φ2 = otherLatitude * .pi / 180
        let Δφ = (otherLatitude - latitude) * .pi / 180
        let Δλ = (otherLongitude - longitude) * .pi / 180
        let a = sin(Δφ / 2) * sin(Δφ / 2) + cos(φ1) * cos(φ2) * sin(Δλ / 2) * sin(Δλ / 2)
        return 2 * radius * atan2(a.squareRoot(), (1 - a).squareRoot())
    }
}

public protocol StoreSearching: Sendable {
    func nearby(latitude: Double, longitude: Double, radiusMeters: Double) async throws -> [StoreResult]
    func search(text: String, latitude: Double, longitude: Double) async throws -> [StoreResult]
    /// Addresses and places (streets, towns) for moving the map there.
    func places(text: String, latitude: Double, longitude: Double) async throws -> [PlaceResult]
}

/// An address or place from a search; the store picker moves the map to it.
public struct PlaceResult: Sendable, Equatable, Hashable, Identifiable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var coordinate: Coordinate

    public init(id: String, title: String, subtitle: String? = nil, coordinate: Coordinate) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.coordinate = coordinate
    }
}

public struct Coordinate: Sendable, Equatable, Hashable {
    public var latitude: Double
    public var longitude: Double

    public init(latitude: Double, longitude: Double) {
        self.latitude = latitude
        self.longitude = longitude
    }
}

public enum LocationAccess: Sendable, Equatable {
    case notDetermined, denied, authorized
}

/// When In Use location only (§6.7). The app implements it with Core Location.
@MainActor
public protocol LocationAuthorizing: AnyObject {
    var access: LocationAccess { get }
    func requestWhenInUse() async -> LocationAccess
    func currentCoordinate() async -> Coordinate?
}
