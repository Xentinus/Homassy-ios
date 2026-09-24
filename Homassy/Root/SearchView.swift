import CoreData
import HomassyCore
import SwiftUI

/// The Search tab: the active space's products by name, brand, category or barcode, typed or scanned
/// (user request, 2026-09-24). A result opens the product detail; an unknown scanned code offers a new product.
struct SearchView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: ProductListModel?
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
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                BarcodeSearchButton(identifier: "search.barcode") { code, symbology in
                    model?.searchBarcode(code, symbology: symbology)
                }
            }
        }
        .task(id: selection.selectedSpaceID) { rebuildModel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model?.reload() }
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
        let cards = model.searchText.trimmingCharacters(in: .whitespaces).isEmpty ? [] : model.sections.flatMap(\.cards)
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(cards) { card in
                    NavigationLink(value: ProductRoute(id: card.id)) { ProductCard(card: card) }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("search.row.\(card.name)")
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if model.searchText.trimmingCharacters(in: .whitespaces).isEmpty {
                ContentUnavailableView("search.prompt", systemImage: "magnifyingglass",
                                       description: Text("search.prompt.message"))
            } else if cards.isEmpty {
                ContentUnavailableView {
                    Label("search.noResults", systemImage: "magnifyingglass")
                } description: {
                    Text(model.unknownBarcode == nil ? "search.noResults.message" : "search.unknownBarcode.message")
                } actions: {
                    if let code = model.unknownBarcode, model.canEdit {
                        Button("search.createProduct") { creatingProduct = code }
                            .buttonStyle(.borderedProminent)
                            .accessibilityIdentifier("search.createProduct")
                    }
                }
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
