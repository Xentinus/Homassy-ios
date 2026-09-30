import Foundation

/// Hands a tick from an App Intent to the app (N-04; N-05's widget tick reuses it). The app registers its handler in
/// `application(_:didFinishLaunchingWithOptions:)`, which also runs when the system launches the app in the
/// background for a `LiveActivityIntent`. The widget extension never registers one, so there `tick` returns false.
@MainActor
public enum ShoppingTickBridge {
    public typealias Handler = @MainActor ([UUID]) async -> Void

    private static var handler: Handler?

    public static var isRegistered: Bool { handler != nil }

    public static func register(_ handler: @escaping Handler) {
        self.handler = handler
    }

    public static func unregister() {
        handler = nil
    }

    @discardableResult
    public static func tick(_ itemIDs: [UUID]) async -> Bool {
        guard let handler else { return false }
        await handler(itemIDs)
        return true
    }
}
