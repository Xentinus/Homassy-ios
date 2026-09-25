import HomassyCore
import SwiftUI

/// The purchased checkbox at the front of an item card. It is its own control, so ticking stays one tap
/// while the rest of the card opens the item (README "Card layout").
struct ShoppingItemCheckbox: View {
    let row: ShoppingListModel.Row
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: row.isPurchased ? "checkmark.circle.fill" : "circle")
                .font(.title2)
                .foregroundStyle(row.isPurchased ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text(verbatim: row.name))
        .accessibilityValue(Text(row.isPurchased ? LocalizedStringKey("shopping.item.state.purchased")
                                                 : LocalizedStringKey("shopping.item.state.open")))
        .accessibilityHint(Text("shopping.item.hint"))
        .accessibilityAddTraits(row.isPurchased ? .isSelected : [])
        .accessibilityIdentifier("shopping.item.\(row.name).toggle")
    }
}

/// The body of an item card: thumbnail, name, quantity and store, deadline and note.
struct ShoppingItemCardContent: View {
    let row: ShoppingListModel.Row

    var body: some View {
        HStack(spacing: 12) {
            ProductImageView(data: row.image, size: 44)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: row.name)
                    .font(.headline)
                    .strikethrough(row.isPurchased)
                    .foregroundStyle(row.isPurchased ? .secondary : .primary)
                HStack(spacing: 8) {
                    Text(verbatim: row.quantityText)
                    if let store = row.storeName {
                        Label { Text(verbatim: store) } icon: { Image(systemName: "storefront") }
                    }
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
                if let deadline = row.deadline {
                    Label {
                        Text("shopping.item.deadline \(deadline.formatted(.dateTime.month(.abbreviated).day()))")
                    } icon: {
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                if let note = row.note {
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
