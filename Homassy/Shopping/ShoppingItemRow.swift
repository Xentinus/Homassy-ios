import HomassyCore
import SwiftUI

/// One item on the Shopping tab (P2-08d, user pick 2A): thumbnail, name and store (or its list, when grouped by
/// store), then the quantity and the deadline on the trailing side. A note shows as a glyph; its text is the card's
/// accessibility value, read last by VoiceOver and shown on the purchase sheet. A deadline within 14 days is yellow,
/// a passed one red, like expiry. A tap opens the purchase sheet.
struct ShoppingItemCard: View {
    let row: ShoppingOverviewModel.Row
    /// Store grouping (P4-03a): the store is the section title, so the card names the list instead.
    var showsList = false
    let open: () -> Void

    @Environment(StoreDirectory.self) private var directory
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .accessibilityHint(Text("shopping.item.openPurchaseHint"))
            .accessibilityIdentifier("shopping.item.\(row.name)")
    }

    private var content: some View {
        WideCardLayout(image: row.image, name: row.name, level: row.deadlineLevel) {
            Text(verbatim: row.name)
                .font(.headline)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .multilineTextAlignment(.leading)
            AttributionCaption(ids: [row.id]) { place }
        } trailing: {
            HStack(spacing: 4) {
                if row.note != nil {
                    Image(systemName: "text.bubble")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: row.quantityText).font(.headline).monospacedDigit()
            }
            if let deadline = row.deadline {
                let day = deadline.formatted(.dateTime.month(.abbreviated).day())
                ExpiryLabel(Text(verbatim: day), level: row.deadlineLevel)
                    .font(.caption.weight(.medium))
                    .accessibilityLabel(Text("shopping.item.deadline \(day)"))
            }
        }
        .attributionRing([row.id])
        .accessibilityElement(children: .combine)
        .accessibilityValue(row.note.map { Text("shopping.item.note \($0)") } ?? Text(verbatim: ""))
    }

    @ViewBuilder private var place: some View {
        if showsList {
            Label {
                Text(verbatim: row.listName)
            } icon: {
                Image(systemName: "circle.fill").foregroundStyle(ListColor.color(row.listColor))
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        } else if let store = row.storeName {
            Label { Text(verbatim: directory.compactName(ofStore: row.storeID) ?? store) }
                icon: { Image(systemName: "storefront") }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
