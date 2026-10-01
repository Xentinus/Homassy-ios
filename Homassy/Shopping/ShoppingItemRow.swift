import HomassyCore
import SwiftUI

/// One item on the Shopping card grid (README "Card layout"): picture, name, quantity, store (or its list, when
/// grouped by store), deadline and note.
/// A deadline within 14 days draws the card yellow, a passed one red, exactly like stock expiry.
/// A tap opens the purchase sheet.
struct ShoppingItemCard: View {
    let row: ShoppingOverviewModel.Row
    /// Store grouping (P4-03a): the store is the section title, so the card names the list instead.
    var showsList = false
    let open: () -> Void

    @Environment(StoreDirectory.self) private var directory

    var body: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .accessibilityHint(Text("shopping.item.openPurchaseHint"))
            .accessibilityIdentifier("shopping.item.\(row.name)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductImageTile(data: row.image, name: row.name)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: row.quantityText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if showsList {
                    Label {
                        Text(verbatim: row.listName)
                    } icon: {
                        Image(systemName: "circle.fill").foregroundStyle(ListColor.color(row.listColor))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                } else if let store = row.storeName {
                    Label { Text(verbatim: directory.compactName(ofStore: row.storeID) ?? store) }
                        icon: { Image(systemName: "storefront") }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let deadline = row.deadline {
                    ExpiryLabel(Text("shopping.item.deadline \(deadline.formatted(.dateTime.month(.abbreviated).day()))"),
                                level: row.deadlineLevel)
                        .font(.caption.weight(.medium))
                        .lineLimit(3)
                }
                AttributionCaption(ids: [row.id]) {
                    if let note = row.note {
                        Text(verbatim: note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome(level: row.deadlineLevel)
        .attributionRing([row.id])
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}
