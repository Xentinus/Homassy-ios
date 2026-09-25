import Foundation

/// The store chosen in the purchase sheet or the add flow: a saved store, or an Apple Maps place that is
/// only stored (`ShoppingLocationService.upsert`) when the sheet is confirmed. A GPS suggestion fills it
/// only while the user has not chosen anything and nothing was preset.
@MainActor
struct StoreSelection {
    enum Source {
        case saved(ShoppingLocation)
        case place(StoreResult)
    }

    private(set) var source: Source?
    private(set) var suggestedDistance: Double?
    private var locked: Bool

    init(preset: ShoppingLocation?) {
        source = preset.map(Source.saved)
        locked = preset != nil
    }

    var name: String? {
        switch source {
        case .saved(let location): location.name
        case .place(let place): place.name
        case nil: nil
        }
    }

    var id: String? {
        switch source {
        case .saved(let location): location.publicId.uuidString
        case .place(let place): place.mapItemIdentifier
        case nil: nil
        }
    }

    mutating func choose(_ location: ShoppingLocation?) {
        source = location.map(Source.saved)
        suggestedDistance = nil
        locked = true
    }

    mutating func apply(_ suggestion: StoreSuggestion, locations: ShoppingLocationService, space: Space) {
        guard !locked else { return }
        switch suggestion {
        case .saved(let id, _, let distance):
            guard let location = try? locations.location(publicId: id, in: space) else { return }
            source = .saved(location)
            suggestedDistance = distance
        case .place(let place, let distance):
            source = .place(place)
            suggestedDistance = distance
        }
    }

    /// The store to write, storing a suggested Apple Maps place first.
    func resolve(locations: ShoppingLocationService, space: Space) throws -> ShoppingLocation? {
        switch source {
        case .saved(let location): location
        case .place(let place): try locations.upsert(place, in: space)
        case nil: nil
        }
    }
}
