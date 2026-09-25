import HomassyCore
import SwiftUI

/// Picks which products of the archive are imported. "All" and "None" act on the rows the search shows.
struct ImportProductPicker: View {
    let model: ArchiveImportModel
    @State private var query = ""

    private var visible: [ArchiveImportModel.ProductOption] {
        let text = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return model.productOptions }
        return model.productOptions.filter { option in
            [option.name, option.brand, option.barcode].compactMap { $0 }
                .contains { $0.localizedStandardContains(text) }
        }
    }

    var body: some View {
        List(visible) { option in
            let isSelected = model.selectedProductIDs.contains(option.id)
            Button {
                model.setProducts([option.id], selected: !isSelected)
            } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: option.name).foregroundStyle(.primary)
                        let detail = [option.brand, option.category].compactMap { $0 }.joined(separator: " · ")
                        if !detail.isEmpty {
                            Text(verbatim: detail).font(.footnote).foregroundStyle(.secondary)
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
            .accessibilityIdentifier("import.product.\(option.name)")
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("archive.import.products.search"))
        .navigationTitle(Text("archive.import.products.title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("archive.import.products.all") { model.setProducts(Set(visible.map(\.id)), selected: true) }
                    .accessibilityIdentifier("import.products.all")
                Spacer()
                Button("archive.import.products.none") { model.setProducts(Set(visible.map(\.id)), selected: false) }
                    .accessibilityIdentifier("import.products.none")
            }
        }
    }
}
