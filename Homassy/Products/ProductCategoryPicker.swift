import HomassyCore
import SwiftUI

/// The product form's category list (P2-07b, 2A): search, "Nincs kategória", the household's categories with the
/// current one ticked, and a "„x” új kategóriaként" row when the search names none (the stock picker's
/// "„x” új termékként" row, the Reminders list picker). A tap picks and goes back.
struct ProductCategoryPicker: View {
    let model: ProductFormModel
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let new = model.newCategory(from: query) {
                Section {
                    Button { pick(new) } label: {
                        Label { Text("product.category.createNamed \(new)") } icon: { Image(systemName: "plus") }
                    }
                    .accessibilityIdentifier("category.create")
                }
            }
            Section {
                if query.isEmpty { row(nil) }
                ForEach(model.categories(matching: query), id: \.self) { row($0) }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("product.category.search"))
        .navigationTitle("product.field.category")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ category: String?) -> some View {
        let selected = switch (category, model.categoryText) {
        case (nil, nil): true
        case let (a?, b?): a.compare(b, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        default: false
        }
        return Button { pick(category ?? "") } label: {
            HStack {
                if let category { Text(verbatim: category) } else { Text("product.category.none") }
                Spacer()
                if selected {
                    Image(systemName: "checkmark").fontWeight(.semibold).foregroundStyle(.tint)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(category.map { "category.row.\($0)" } ?? "category.none")
    }

    private func pick(_ category: String) {
        model.draft.category = category
        dismiss()
    }
}

#if DEBUG
#Preview {
    let app = AppModel.preview()
    NavigationStack {
        ProductCategoryPicker(model: ProductFormModel(mode: .create(app.personalSpace!, barcode: nil),
                                                     service: app.services!.products))
    }
}
#endif
