import Foundation
import LarariShared

public enum ShoppingActivityDismissal: Equatable, Sendable {
    case immediate
    case systemDefault
    case after(Date)
}

public struct ShoppingActivityRequest: Equatable, Sendable {
    public let spaceID: UUID
    public let scope: ShoppingActivityScope
    public let content: ShoppingActivityContent
    public let staleDate: Date?
    public let relevance: Double

    public init(spaceID: UUID, scope: ShoppingActivityScope, content: ShoppingActivityContent, staleDate: Date?,
                relevance: Double) {
        self.spaceID = spaceID
        self.scope = scope
        self.content = content
        self.staleDate = staleDate
        self.relevance = relevance
    }
}

/// An activity the system still shows (active or stale), possibly started by an earlier app process.
public struct RunningShoppingActivity: Equatable, Sendable {
    public let id: String
    public let spaceID: UUID
    public let scope: ShoppingActivityScope
    public let content: ShoppingActivityContent

    public init(id: String, spaceID: UUID, scope: ShoppingActivityScope, content: ShoppingActivityContent) {
        self.id = id
        self.spaceID = spaceID
        self.scope = scope
        self.content = content
    }
}

public enum ShoppingActivityError: Error, Equatable {
    case unavailable
}

/// ActivityKit behind a protocol, so the coordinator is tested on the Mac. The app's `ActivityKitShoppingController`
/// is the real one; LarariCore never imports ActivityKit.
@MainActor
public protocol LiveActivityControlling: AnyObject {
    var areActivitiesEnabled: Bool { get }
    func running() -> [RunningShoppingActivity]
    func start(_ request: ShoppingActivityRequest) throws -> String
    func update(id: String, content: ShoppingActivityContent, staleDate: Date?, relevance: Double) async
    func end(id: String, content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async
}

/// Package tests and previews: Live Activities are switched off.
@MainActor
public final class NoLiveActivities: LiveActivityControlling {
    public init() {}
    public var areActivitiesEnabled: Bool { false }
    public func running() -> [RunningShoppingActivity] { [] }
    public func start(_ request: ShoppingActivityRequest) throws -> String { throw ShoppingActivityError.unavailable }
    public func update(id: String, content: ShoppingActivityContent, staleDate: Date?, relevance: Double) async {}
    public func end(id: String, content: ShoppingActivityContent?, dismissal: ShoppingActivityDismissal) async {}
}
