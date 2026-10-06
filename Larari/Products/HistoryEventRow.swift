import LarariCore
import SwiftUI

struct HistoryEventRow: View {
    let row: HistoryRow

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// At the accessibility sizes the quantity goes under the kind and the date under the actor, so "Consumed" is not
    /// hyphenated and the date does not squeeze into a narrow column beside the name (X-04).
    private func lineLayout(spacing: CGFloat? = nil) -> AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: spacing))
    }

    var body: some View {
        let titleLine = lineLayout()
        let actorLine = lineLayout(spacing: 6)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.kind.glyph)
                .foregroundStyle(Palette.mocha600)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                titleLine {
                    Text(row.kind.title)
                    Text(row.quantityText).monospacedDigit().foregroundStyle(.secondary)
                }
                if let places = placesText {
                    Text(places).font(.caption).foregroundStyle(.secondary)
                }
                actorLine {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.memberAccent(seed: row.actorSeed))
                            .frame(width: 8, height: 8)
                            .accessibilityHidden(true)
                        actorText.font(.caption)
                    }
                    if let date = row.occurredAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actorText: Text {
        if row.isCurrentUser { return Text("history.actor.you") }
        if let name = row.actorName { return Text(name) }
        return Text("history.actor.someone")
    }

    private var placesText: String? {
        switch (row.fromLocation, row.toLocation) {
        case let (from?, to?): "\(from) → \(to)"
        case let (from?, nil): from
        case let (nil, to?): "→ \(to)"
        case (nil, nil): nil
        }
    }
}

private extension InventoryEventKind {
    var title: LocalizedStringKey {
        switch self {
        case .added: "history.kind.added"
        case .consumed: "history.kind.consumed"
        case .moved: "history.kind.moved"
        case .deleted: "history.kind.deleted"
        case .edited: "history.kind.edited"
        }
    }

    var glyph: String {
        switch self {
        case .added: "plus.circle"
        case .consumed: "fork.knife"
        case .moved: "arrow.right.arrow.left"
        case .deleted: "trash"
        case .edited: "pencil"
        }
    }
}
