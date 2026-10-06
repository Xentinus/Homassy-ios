import LarariCore
import SwiftUI

/// The list filter under the title (P4-03a): "All" and one chip per list with its colour dot and count, in list
/// order. A long press on a list chip offers Edit and Delete; VoiceOver gets them as actions. On iPad the menu
/// starts with Open in New Window, and a chip dragged to the screen edge becomes a list window (N-03).
struct ShoppingFilterStrip: View {
    let chips: [ShoppingOverviewModel.ListChip]
    let total: Int
    @Binding var filter: UUID?
    let edit: (UUID) -> Void
    let delete: (UUID) -> Void
    @Environment(\.supportsMultipleWindows) private var supportsMultipleWindows

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                chip(id: nil, name: String(localized: "shopping.filter.all"), color: nil, count: total,
                     identifier: "shopping.filter.all")
                ForEach(chips) { item in
                    chip(id: item.id, name: item.name, color: item.color, count: item.remaining,
                         identifier: "shopping.filter.\(item.name)")
                        .contextMenu {
                            OpenInNewWindowMenuItems(route: .shoppingList(item.id))
                            actions(item.id)
                        }
                        .accessibilityActions {
                            if supportsMultipleWindows { OpenInNewWindowButton(route: .shoppingList(item.id)) }
                            actions(item.id)
                        }
                        .draggableIntoWindow(.shoppingList(item.id))
                }
            }
            .padding(.horizontal)
        }
        .scrollIndicators(.hidden)
    }

    private func chip(id: UUID?, name: String, color: String?, count: Int, identifier: String) -> some View {
        let selected = filter == id
        return Button { filter = id } label: {
            HStack(spacing: 6) {
                if id != nil {
                    Circle().fill(ListColor.color(color)).frame(width: 8, height: 8)
                }
                Text(verbatim: name).lineLimit(1)
                Text(verbatim: count.formatted()).monospacedDigit().opacity(0.7)
            }
            .font(.subheadline.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .foregroundStyle(selected ? Color(uiColor: .systemBackground) : Color.primary)
            .background(selected ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
            .padding(.vertical, 4)                         // a 44 pt tall hit area around the capsule
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityValue(Text("shopping.lists.remaining \(count)"))
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }

    @ViewBuilder private func actions(_ id: UUID) -> some View {
        Button { edit(id) } label: { Label("common.edit", systemImage: "pencil") }
        Button(role: .destructive) { delete(id) } label: { Label("common.delete", systemImage: "trash") }
    }
}
