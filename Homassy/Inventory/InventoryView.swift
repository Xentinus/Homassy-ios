import CoreData
import HomassyCore
import SwiftUI

/// The Inventory tab root: "Expiring soon", then the storage locations, then "No location", as product cards.
/// Cards have no actions of their own (user rule); a tap opens the product detail.
struct InventoryView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var model: InventoryModel?
    @State private var addingStock = false
    @State private var creatingProduct = false
    @State private var scanning = false

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("inventory.title")
        .navigationDestination(for: ProductRoute.self) { ProductDetailView(productID: $0.id) }
        .toolbar { toolbar }
        .task(id: selection.selectedSpaceID) { rebuildModel() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model?.reload() }
        .barcodeFlow(isScanning: $scanning, space: model?.space)
        .sheet(isPresented: $addingStock) {
            if let space = model?.space { StockAddSheet.picking(in: space, services: services) }
        }
        .sheet(isPresented: $creatingProduct) {
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
    private func content(_ model: InventoryModel) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12, pinnedViews: [.sectionHeaders]) {
                ForEach(model.sections) { section in
                    Section {
                        ForEach(section.cards.map { SectionCard(section: section.id, card: $0) }) { entry in
                            let card = entry.card
                            NavigationLink(value: ProductRoute(id: card.id)) { ProductCard(card: card) }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("inventory.row.\(card.name)")
                        }
                    } header: {
                        header(section)
                    }
                }
            }
            .padding(.horizontal)
            .padding(.bottom, 24)
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BackupReminderBanner(space: model.space)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityIdentifier("inventory.grid")
        .overlay {
            if model.isEmpty {
                ContentUnavailableView {
                    Label("inventory.empty.title", systemImage: "refrigerator")
                } description: {
                    Text("inventory.empty.message")
                } actions: {
                    if model.canEdit {
                        Button("inventory.addStock") { addingStock = true }
                            .buttonStyle(.borderedProminent)
                    }
                }
            }
        }
        .alert("common.error", isPresented: Binding(get: { model.errorMessage != nil },
                                                    set: { if !$0 { model.dismissError() } })) {
            Button("common.ok", role: .cancel) {}
        } message: { Text(model.errorMessage ?? "") }
    }

    private func header(_ section: InventorySection) -> some View {
        HStack(spacing: 6) {
            switch section.kind {
            case .expiring:
                Image(systemName: "clock").foregroundStyle(Palette.expirySoon)
                Text("inventory.section.expiring")
            case .location:
                Image(systemName: section.isFreezer ? "snowflake" : "archivebox")
                Text(section.title ?? "")
            case .noLocation:
                Image(systemName: "tray")
                Text("inventory.noLocation")
            }
        }
        .font(.headline)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(sectionIdentifier(section))
    }

    private func sectionIdentifier(_ section: InventorySection) -> String {
        switch section.kind {
        case .expiring: "inventory.section.expiring"
        case .location: "inventory.section.\(section.title ?? "")"
        case .noLocation: "inventory.section.none"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        SpaceSwitcherToolbarItem()
        ToolbarItem(placement: .primaryAction) {
            AddMenu {
                Button { addingStock = true } label: { Label("add.inventoryItem", systemImage: "plus.circle") }
                    .accessibilityIdentifier("addMenu.stock")
                Button { creatingProduct = true } label: { Label("add.product", systemImage: "shippingbox") }
                    .accessibilityIdentifier("addMenu.product")
                Button { scanning = true } label: { Label("barcode.scan", systemImage: "barcode.viewfinder") }
                    .accessibilityIdentifier("addMenu.barcode")
            }
            .disabled(model?.canEdit != true)
        }
    }

    private func rebuildModel() {
        guard let space = services.activeSpace(selectedID: selection.selectedSpaceID) else { return }
        if model?.space == space { model?.reload(); return }
        let fresh = InventoryModel(inventory: services.inventory, storage: services.storageLocations, space: space,
                                   pending: services.pendingDeletions)
        fresh.reload()
        model = fresh
    }
}

/// A product can have a card in several sections (lots in different places). The lazy grid needs ids that are
/// unique across all sections, or it draws only one of the cards.
private struct SectionCard: Identifiable {
    struct ID: Hashable {
        let section: InventorySection.Kind
        let product: UUID
    }

    let section: InventorySection.Kind
    let card: ProductCardData
    var id: ID { ID(section: section, product: card.id) }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { InventoryView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { InventoryView() }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
        .environment(ArchiveImportRouter()).environment(BackupReminder(defaults: UserDefaults(suiteName: "HomassyPreview")!))
}
#endif
