import Foundation
import Observation

/// The "Honnan" pull-down menu shared by the add-stock sheet and the purchase sheet (P2-08a, option A): the GPS
/// suggestion, the recent stores (this product's first), "Other store…" and "No store". The user picks; the GPS
/// only suggests and fills an untouched menu.
@MainActor
@Observable
public final class StoreMenuModel {
    public private(set) var options: [PickerOption] = []
    public private(set) var suggestion: StoreSuggestion?
    private var selection: StoreSelection

    @ObservationIgnored private let locations: ShoppingLocationService
    @ObservationIgnored private let space: Space?
    @ObservationIgnored private var product: Product?

    public init(preset: ShoppingLocation?, product: Product?, space: Space?, locations: ShoppingLocationService) {
        selection = StoreSelection(preset: preset)
        self.locations = locations
        self.space = space
        self.product = product
        reload()
        if let preset { pin(preset) }
    }

    public var name: String? { selection.name }
    /// Metres to the store while it is the untouched GPS suggestion.
    public var suggestedDistance: Double? { selection.suggestedDistance }
    public var selectedStoreID: UUID? { selection.savedLocation?.publicId }

    /// The suggestion gets its own menu entry while it is not already the choice.
    public var offersSuggestion: Bool {
        guard let suggestion, selection.suggestedDistance == nil else { return false }
        if case .saved(let id, _, _) = suggestion, id == selectedStoreID { return false }
        return true
    }

    public func setProduct(_ product: Product?) {
        self.product = product
        reload()
    }

    /// A recent store from the menu; nil is "No store".
    public func choose(_ id: UUID?) {
        guard let id else {
            selection.choose(nil)
            return
        }
        guard let space, let store = try? locations.location(publicId: id, in: space) else { return }
        selection.choose(store)
    }

    /// From "Other store…": the pick goes to the top of the recent entries until the sheet closes.
    public func setStore(_ store: ShoppingLocation?) {
        selection.choose(store)
        if let store { pin(store) }
    }

    public func applySuggestion(_ suggestion: StoreSuggestion) {
        guard let space else { return }
        self.suggestion = suggestion
        selection.apply(suggestion, locations: locations, space: space)
    }

    public func chooseSuggestion() {
        guard let space, let suggestion else { return }
        selection.take(suggestion, locations: locations, space: space)
    }

    /// The store to write; a suggested Apple Maps place is stored first.
    func resolve() throws -> ShoppingLocation? {
        guard let space else { return nil }
        return try selection.resolve(locations: locations, space: space)
    }

    private func reload() {
        guard let space else { return }
        let stores = (try? locations.recentStores(for: product, in: space)) ?? []
        options = stores.map { PickerOption(id: $0.publicId, name: $0.name) }
    }

    private func pin(_ store: ShoppingLocation) {
        guard !options.contains(where: { $0.id == store.publicId }) else { return }
        options.insert(PickerOption(id: store.publicId, name: store.name), at: 0)
    }
}
