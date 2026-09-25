import HomassyCore
import SwiftUI

/// The checkbox at the front of an item card: buys the whole quantity into inventory in one tap
/// (undoable). The rest of the card opens the purchase sheet.
struct ShoppingItemCheckbox: View {
    let row: ShoppingListModel.Row
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(Text("shopping.item.markBought \(row.name)"))
        .accessibilityHint(Text("shopping.item.hint"))
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
