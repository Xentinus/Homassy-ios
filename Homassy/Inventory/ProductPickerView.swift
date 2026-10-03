import HomassyCore
import SwiftUI

/// The add-stock sheet's first page (P2-08a, option 1A): recent products, A–Z sections with the letter strip,
/// search, a barcode button, and "Create “x”" when nothing has exactly that name.
struct ProductPickerView: View {
    @Bindable var model: ProductPickerModel
    let onCancel: () -> Void
    let onPick: (UUID) -> Void

    private struct NewProduct: Identifiable {
        let id = UUID()
        let name: String?
        let barcode: String?
    }

    @Environment(ServiceContainer.self) private var services
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var newProduct: NewProduct?
    @State private var scanning = false
    @State private var pendingPick: UUID?
    @State private var pendingNew: NewProduct?

    var body: some View {
        ScrollViewReader { proxy in
            List {
                if !model.recents.isEmpty {
                    Section("picker.recent") {
                        ForEach(model.recents) { row($0).id("recent-\($0.id)") }
                    }
                }
                if model.isSearching {
                    Section("picker.products") {
                        ForEach(model.sections.flatMap(\.products)) { row($0) }
                    }
                    if let name = model.createCandidate, model.canCreate {
                        Section {
                            Button { newProduct = NewProduct(name: name, barcode: nil) } label: {
                                Label { Text("picker.createNamed \(name)") } icon: { Image(systemName: "plus") }
                            }
                            .accessibilityIdentifier("picker.create")
                        }
                    }
                } else {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.products) { row($0).id($0.id) }
                        } header: {
                            Text(verbatim: section.id)
                        }
                    }
                }
            }
            .overlay(alignment: .trailing) {
                // Hidden at accessibility sizes, like the Search index (X-04).
                if !model.isSearching, model.sections.count > 1, !dynamicTypeSize.isAccessibilitySize {
                    SectionIndexBar(letters: model.sections.map(\.id)) { letter in
                        if let first = model.sections.first(where: { $0.id == letter })?.products.first {
                            proxy.scrollTo(first.id, anchor: .top)
                        }
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .overlay {
            if model.sections.isEmpty, !model.isSearching {
                ContentUnavailableView {
                    Label("picker.empty", systemImage: "shippingbox")
                } actions: {
                    if model.canCreate {
                        Button("add.product") { newProduct = NewProduct(name: nil, barcode: nil) }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("stock.title.add")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { SheetCancelButton(action: onCancel) }
            ToolbarItemGroup(placement: .primaryAction) {
                Button { scanning = true } label: { Label("search.byBarcode", systemImage: "barcode.viewfinder") }
                    .accessibilityIdentifier("picker.barcode")
                if model.canCreate {
                    Button { newProduct = NewProduct(name: model.createCandidate, barcode: nil) } label: {
                        Label("add.product", systemImage: "plus")
                    }
                    .accessibilityIdentifier("picker.new")
                }
            }
        }
        .sheet(isPresented: $scanning, onDismiss: afterScan) {
            BarcodeScannerSheet { code, symbology in
                guard scanning else { return }
                scanning = false
                switch model.route(barcode: code, symbology: symbology) {
                case .known(let product): pendingPick = product.publicId
                case .unknown(let barcode): pendingNew = NewProduct(name: nil, barcode: barcode)
                case nil: break
                }
            }
        }
        .sheet(item: $newProduct, onDismiss: afterScan) { seed in
            ProductFormSheet(model: ProductFormModel(mode: .create(model.space, barcode: seed.barcode, name: seed.name),
                                                     service: services.products)) { product in
                model.reload()
                pendingPick = product.publicId
            }
        }
        .alert("common.error", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.dismissError() } })) {
            Button("common.ok", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private func row(_ product: PickerProduct) -> some View {
        Button { onPick(product.id) } label: {
            HStack(spacing: 12) {
                ProductImageView(data: product.image, size: 36, name: product.name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: product.name).foregroundStyle(.primary)
                    if let subtitle = product.subtitle {
                        Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityIdentifier("picker.row.\(product.name)")
    }

    /// Sheets close first; then a found or created product opens its details, or an unknown code opens the form.
    private func afterScan() {
        if let id = pendingPick {
            pendingPick = nil
            onPick(id)
        } else if let seed = pendingNew {
            pendingNew = nil
            newProduct = seed
        }
    }
}
