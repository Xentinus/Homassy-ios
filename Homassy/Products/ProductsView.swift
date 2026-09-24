import CoreData
import HomassyCore
import SwiftUI

/// Navigation value for a product detail. Codable, so the tab's restored path can hold it.
struct ProductRoute: Hashable, Codable {
    let id: UUID
}

/// The Products tab root: letter sections of product cards, search and a category filter.
/// Cards have no delete (user rule); a tap opens the product detail.
struct ProductsView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: ProductListModel?
    @State private var showingForm = false
    @State private var scanning = false

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("products.title")
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
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
    }

    @ViewBuilder
    private func content(_ model: ProductListModel) -> some View {
        @Bindable var model = model
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
                        Text(section.id)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 4)
                            .background(Color(uiColor: .systemGroupedBackground))
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(text: $model.searchText, placement: .navigationBarDrawer(displayMode: .always),
                    prompt: Text("products.search.prompt"))
        .overlay {
            if model.sections.isEmpty {
                if model.isFiltering {
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

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) { SpaceSwitcher() }
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
    NavigationStack { ProductsView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { ProductsView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}
#endif
