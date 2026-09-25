import HomassyCore
import SwiftUI

/// One item on the list's card grid (README "Card layout"): picture, name, quantity, store, deadline and note,
/// with the checkbox in the corner. The checkbox buys the whole quantity into inventory; a tap on the card
/// opens the purchase sheet.
struct ShoppingItemCard: View {
    let row: ShoppingListModel.Row
    let open: () -> Void
    let buy: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Button(action: open) { content }
                .buttonStyle(.plain)
                .accessibilityHint(Text("shopping.item.openPurchaseHint"))
                .accessibilityIdentifier("shopping.item.\(row.name)")
            ShoppingItemCheckbox(row: row, toggle: buy)
                .padding(4)
        }
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
                        Image(systemName: "calendar")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                }
                if let note = row.note {
                    Text(verbatim: note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardChrome()
        .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// The checkbox in the card's corner: buys the whole quantity into inventory in one tap (undoable).
struct ShoppingItemCheckbox: View {
    let row: ShoppingListModel.Row
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            Image(systemName: "circle")
                .font(.title2)
                .foregroundStyle(Palette.mocha600)
                .padding(6)
                .background(.regularMaterial, in: Circle())
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("shopping.item.markBought \(row.name)"))
        .accessibilityHint(Text("shopping.item.hint"))
        .accessibilityIdentifier("shopping.item.\(row.name).toggle")
    }
}
