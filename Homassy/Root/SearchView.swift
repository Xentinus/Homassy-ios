import CoreData
import HomassyCore
import SwiftUI

/// The Search tab and the product catalogue in one (P1-07a, user decision 2026-09-26; search itself is a user
/// request of 2026-09-24). An empty field shows every product of the active space in letter sections; typing, a
/// category or a scanned barcode narrows them. Cards have no delete (user rule); a tap opens the product detail.
/// An unknown scanned code offers a new product.
struct SearchView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: ProductListModel?
    @State private var showingForm = false
    @State private var scanning = false
    @State private var creatingProduct: String?

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle(AppTab.search.title)
        // Explicit drawer placement: with the default placement the search-role tab showed no field at all.
        .searchable(text: Binding(get: { model?.searchText ?? "" }, set: { model?.searchText = $0 }),
                    placement: .navigationBarDrawer(displayMode: .always), prompt: Text("products.search.prompt"))
        .navigationDestination(for: ProductRoute.self) { ProductDetailView(productID: $0.id) }
        .toolbar { toolbar }
        .task(id: selection.selectedSpaceID) { rebuildModel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model?.reload() }
        .barcodeFlow(isScanning: $scanning, space: model?.space)
        .sheet(isPresented: $showingForm) {
            if let space = model?.space {
                ProductFormSheet(model: ProductFormModel(mode: .create(space, barcode: nil), service: services.products))
            }
        }
        .sheet(item: Binding(get: { creatingProduct.map(BarcodeValue.init) }, set: { creatingProduct = $0?.code })) { value in
            if let space = model?.space {
                ProductFormSheet(model: ProductFormModel(mode: .create(space, barcode: value.code), service: services.products)) { _ in
                    model?.searchBarcode(value.code)
                }
            }
        }
    }

    private struct BarcodeValue: Identifiable {
        let code: String
        var id: String { code }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private func content(_ model: ProductListModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.cards) { card in
                                NavigationLink(value: ProductRoute(id: card.id)) { ProductCard(card: card) }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("product.row.\(card.name)")
                            }
                        } header: {
                            // The Text keeps its own width; a row-wide Text frame made the audit misread its contrast.
                            HStack {
                                Text(section.id)
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)
                                    .accessibilityIdentifier("search.section.\(section.id)")
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .id(section.id)
                        }
                    }
                }
                .padding(.leading)
                .padding(.trailing, showsIndex(model) ? 28 : 16)
                .padding(.bottom, 24)
            }
            .overlay(alignment: .trailing) {
                if showsIndex(model) {
                    SectionIndexBar(letters: model.sections.map(\.id)) { letter in
                        proxy.scrollTo(letter, anchor: .top)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if model.sections.isEmpty {
                if let code = model.unknownBarcode {
                    ContentUnavailableView {
                        Label("search.noResults", systemImage: "magnifyingglass")
                    } description: {
                        Text("search.unknownBarcode.message")
                    } actions: {
                        if model.canEdit {
                            Button("search.createProduct") { creatingProduct = code }
                                .buttonStyle(.borderedProminent)
                                .accessibilityIdentifier("search.createProduct")
                        }
                    }
                } else if model.isFiltering {
                    ContentUnavailableView.search(text: model.searchText)
                } else {
                    ContentUnavailableView("products.empty.title", systemImage: "shippingbox",
                                           description: Text("products.empty.message"))
                }
            }
        }
        .alert("common.error", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.dismissError() } })) {
            Button("common.ok", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    /// The letter strip appears once there is more than one letter to jump between.
    /// Hidden at accessibility sizes: the letters cannot grow in the strip and would cover the cards (X-04).
    private func showsIndex(_ model: ProductListModel) -> Bool {
        model.sections.count > 1 && !dynamicTypeSize.isAccessibilitySize
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        SpaceSwitcherToolbarItem()
        ToolbarItem(placement: .topBarTrailing) {
            BarcodeSearchButton(identifier: "search.barcode") { code, symbology in
                model?.searchBarcode(code, symbology: symbology)
            }
        }
        if let model, !model.categories.isEmpty {
            ToolbarItem(placement: .topBarTrailing) {
                @Bindable var model = model
                Menu {
                    Picker("products.filter", selection: $model.selectedCategory) {
                        Text("products.filter.all").tag(String?.none)
                        ForEach(model.categories, id: \.self) { Text($0).tag(Optional($0)) }
                    }
                } label: {
                    Label("products.filter", systemImage: model.selectedCategory == nil
                          ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                }
                .accessibilityIdentifier("products.filter")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            AddMenu {
                Button { showingForm = true } label: { Label("add.product", systemImage: "shippingbox") }
                    .accessibilityIdentifier("addMenu.product")
                    .disabled(model?.canEdit != true)
                Button { scanning = true } label: { Label("barcode.scan", systemImage: "barcode.viewfinder") }
                    .accessibilityIdentifier("addMenu.barcode")
            }
        }
    }

    private func rebuildModel() {
        guard let space = services.activeSpace(selectedID: selection.selectedSpaceID) else { return }
        if model?.space == space { model?.reload(); return }
        let fresh = ProductListModel(products: services.products, inventory: services.inventory, space: space,
                                     pending: services.pendingDeletions)
        fresh.reload()
        model = fresh
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { SearchView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter())
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { SearchView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter())
}
#endif
