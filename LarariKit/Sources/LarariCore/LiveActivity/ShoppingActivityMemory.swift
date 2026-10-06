import Foundation
import LarariShared

/// What the shopping Live Activity remembers across app launches (N-04): the activity this app started, and where
/// the user swiped one away (D9 B: it must not come straight back at the same place).
@MainActor
public final class ShoppingActivityMemory {
    public struct Record: Codable, Equatable, Sendable {
        public let activityID: String
        public let spaceID: UUID
        public let scope: ShoppingActivityScope
        public let center: Coordinate?
    }

    public struct Suppression: Codable, Equatable, Sendable {
        public let spaceID: UUID
        public let scope: ShoppingActivityScope
        public let center: Coordinate?
        public let since: Date
    }

    static let startedKey = "shoppingActivity.started"
    static let suppressedKey = "shoppingActivity.suppressed"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var started: Record? {
        get { read(Self.startedKey) }
        set { write(newValue, Self.startedKey) }
    }

    public var suppressed: Suppression? {
        get { read(Self.suppressedKey) }
        set { write(newValue, Self.suppressedKey) }
    }

    private func read<T: Decodable>(_ key: String) -> T? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }

    private func write<T: Encodable>(_ value: T?, _ key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }
}
