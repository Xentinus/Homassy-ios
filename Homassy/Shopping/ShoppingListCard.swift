import HomassyCore
import SwiftUI

/// One list on the lists overview: its colour dot, name, and how many items are left to buy.
struct ShoppingListCard: View {
    let summary: ShoppingListsModel.Summary

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(ListColor.color(summary.color))
                .frame(width: 14, height: 14)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(verbatim: summary.name).font(.headline).lineLimit(2)
                Text("shopping.lists.remaining \(summary.remaining)")
                    .font(.subheadline)
                .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
