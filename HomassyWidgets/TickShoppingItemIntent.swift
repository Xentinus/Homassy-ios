import AppIntents
import Foundation
import HomassyShared

/// Ticks one row on the shopping Live Activity (N-04): every list item merged into it. A `LiveActivityIntent`, so the
/// system runs `perform` in the app's process and launches the app in the background when needed. Compiled into the
/// app and the widget extension (two target memberships). Not discoverable: no Shortcuts, no Siri (spec §7 as amended).
struct TickShoppingItemIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "activity.intent.tick.title"
    static let isDiscoverable = false

    /// Comma-separated UUIDs; App Intents parameters have no UUID list type.
    @Parameter(title: "activity.intent.tick.item")
    var itemIDs: String

    init() {}

    init(itemIDs: [UUID]) {
        self.itemIDs = itemIDs.map(\.uuidString).joined(separator: ",")
    }

    func perform() async throws -> some IntentResult {
        let ids = itemIDs.split(separator: ",").compactMap { UUID(uuidString: String($0)) }
        if !ids.isEmpty {
            await ShoppingTickBridge.tick(ids)
        }
        return .result()
    }
}
