import HomassyCore
import SwiftUI

/// One item on the list's card grid (README "Card layout"): picture, name, quantity, store, deadline and note.
/// A deadline within 14 days draws the card yellow, a passed one red, exactly like stock expiry.
/// A tap opens the purchase sheet.
struct ShoppingItemCard: View {
    let row: ShoppingListModel.Row
    let open: () -> Void

    var body: some View {
        Button(action: open) { content }
            .buttonStyle(.plain)
            .accessibilityHint(Text("shopping.item.openPurchaseHint"))
            .accessibilityIdentifier("shopping.item.\(row.name)")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            ProductImageTile(data: row.image)
            VStack(alignment: .leading, spacing: 4) {
                Text(verbatim: row.name)
                    .font(.headline)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Text(verbatim: row.quantityText)
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                if let store = row.storeName {
                    Label { Text(verbatim: store) } icon: { Image(systemName: "storefront") }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                if let deadline = row.deadline {
                    Label {
                        Text("shopping.item.deadline \(deadline.formatted(.dateTime.month(.abbreviated).day()))")
                    } icon: {
                        Image(systemName: row.deadlineLevel.cardGlyph)
                    }
                    .font(.caption.weight(.medium))
                    .foregroundStyle(row.deadlineLevel.cardForeground)
                    .lineLimit(1)
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
