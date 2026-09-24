import Foundation
import Observation

/// The space the main screens show. Persisted in UserDefaults so it survives relaunches.
@MainActor
@Observable
public final class SpaceSelection {
    public static let defaultsKey = "selectedSpaceID"

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private var storedID: UUID?

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedID = defaults.string(forKey: Self.defaultsKey).flatMap(UUID.init(uuidString:))
    }

    public var selectedSpaceID: UUID? {
        get {
            access(keyPath: \.selectedSpaceID)
            return storedID
        }
        set {
            withMutation(keyPath: \.selectedSpaceID) { storedID = newValue }
            if let newValue {
                defaults.set(newValue.uuidString, forKey: Self.defaultsKey)
            } else {
                defaults.removeObject(forKey: Self.defaultsKey)
            }
        }
    }

    /// The selected space if it is in `spaces`, otherwise Personal, otherwise the first space.
    /// Does not change `selectedSpaceID`.
    public func resolve(in spaces: [Space]) -> Space? {
        if let id = selectedSpaceID, let match = spaces.first(where: { $0.publicId == id }) {
            return match
        }
        return spaces.first(where: { $0.kind == .personal }) ?? spaces.first
    }

    public func select(_ space: Space) {
        selectedSpaceID = space.publicId
    }
}
