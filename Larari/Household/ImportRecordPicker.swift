import LarariCore
import SwiftUI

/// Picks which records of one group of the archive are imported. "All" and "None" act on the rows the
/// search shows.
struct ImportRecordPicker: View {
    let model: ArchiveImportModel
    let group: ArchiveSelection.Group
    @State private var query = ""

    private var visible: [ArchiveImportModel.RecordOption] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let options = model.options(for: group)
        guard !text.isEmpty else { return options }
        return options.filter { option in
            ([option.title] + option.keywords).contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        let picked = model.pickedIDs(for: group)
        List(visible) { option in
            let isSelected = picked.contains(option.id)
            Button {
                model.setRecords([option.id], in: group, selected: !isSelected)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.title)
                        if let detail = option.detail {
                            Self.text(for: detail).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 8)
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(isSelected ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
            .accessibilityIdentifier("import.record.\(option.title)")
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text(group == .products ? "archive.import.products.search" : "archive.import.search"))
        .navigationTitle(Text(Self.title(for: group)))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("archive.import.pick.all") { model.setRecords(Set(visible.map(\.id)), in: group, selected: true) }
                    .accessibilityIdentifier("import.records.all")
                Spacer()
                Button("archive.import.pick.none") { model.setRecords(Set(visible.map(\.id)), in: group, selected: false) }
                    .accessibilityIdentifier("import.records.none")
            }
        }
    }

    private static func text(for detail: ArchiveImportModel.RecordOption.Detail) -> Text {
        switch detail {
        case .text(let text): Text(verbatim: text)
        case .freezer: Text("storageLocations.form.freezer")
        case .items(let count): Text("archive.import.lists.detail \(count)")
        }
    }

    static func title(for group: ArchiveSelection.Group) -> LocalizedStringKey {
        switch group {
        case .products, .stock: "archive.import.pickTitle.products"
        case .storageLocations: "archive.import.pickTitle.storageLocations"
        case .shoppingLocations: "archive.import.pickTitle.shoppingLocations"
        case .shoppingLists: "archive.import.pickTitle.shoppingLists"
        case .members: "archive.import.pickTitle.members"
        }
    }

    /// "Choose products · 1 / 2"
    static func linkTitle(for group: ArchiveSelection.Group, picked: Int, total: Int) -> Text {
        switch group {
        case .products, .stock: Text("archive.import.pick.products \(picked) \(total)")
        case .storageLocations: Text("archive.import.pick.storageLocations \(picked) \(total)")
        case .shoppingLocations: Text("archive.import.pick.shoppingLocations \(picked) \(total)")
        case .shoppingLists: Text("archive.import.pick.shoppingLists \(picked) \(total)")
        case .members: Text("archive.import.pick.members \(picked) \(total)")
        }
    }
}
