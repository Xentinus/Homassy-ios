#if os(iOS)
import ActivityKit
import Foundation

/// The shopping Live Activity's fixed part (N-04): the household and the store or chain. In LarariShared so the app
/// and the widget extension use one type. `#if os(iOS)` rather than `canImport(ActivityKit)`: the macOS SDK ships
/// ActivityKit with every type marked unavailable, and `swift test` runs on macOS.
public struct ShoppingActivityAttributes: ActivityAttributes {
    public typealias ContentState = ShoppingActivityContent

    public let spaceID: UUID
    public let scope: ShoppingActivityScope

    public init(spaceID: UUID, scope: ShoppingActivityScope) {
        self.spaceID = spaceID
        self.scope = scope
    }
}
#endif
