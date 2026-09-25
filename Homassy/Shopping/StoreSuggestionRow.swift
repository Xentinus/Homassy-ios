import HomassyCore
import SwiftUI

/// The chosen store in the purchase and add sheets, with "nearest, 120 m" when GPS suggested it.
struct StoreSuggestionRow: View {
    let name: String?
    let distance: Double?
    let change: () -> Void

    var body: some View {
        Button(action: change) {
            HStack(spacing: 12) {
                Image(systemName: distance == nil ? "storefront" : "location.fill")
                    .foregroundStyle(.tint)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    if let name {
                        Text(verbatim: name).foregroundStyle(.primary)
                    } else {
                        Text("shopping.form.store.none").foregroundStyle(.primary)
                    }
                    if let distance {
                        Text("store.suggested \(Self.format(distance))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
                Text("store.change").foregroundStyle(.tint)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("store.suggestion")
    }

    static func format(_ metres: Double) -> String {
        Measurement(value: metres.rounded(), unit: UnitLength.meters)
            .formatted(.measurement(width: .abbreviated, usage: .asProvided, numberFormatStyle: .number.precision(.fractionLength(0))))
    }
}

/// Asks for When In Use the first time a store is needed, then offers the nearest shop.
@MainActor
enum StoreSuggestionLoader {
    static func suggestion(for space: Space, services: ServiceContainer,
                           authorizer: CoreLocationAuthorizer) async -> StoreSuggestion? {
        #if DEBUG
        // UI tests never trigger the system location prompt; the suggester has its own unit tests.
        if UITestHooks.isActive { return nil }
        #endif
        if authorizer.access == .notDetermined { _ = await authorizer.requestWhenInUse() }
        let suggester = NearestStoreSuggester(search: services.storeSearch, locations: services.shoppingLocations,
                                              location: authorizer)
        return await suggester.suggestion(in: space)
    }
}
