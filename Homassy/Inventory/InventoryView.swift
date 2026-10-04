import CoreData
import HomassyCore
import SwiftUI

/// The Inventory tab root: product cards grouped by location ("Expiring soon", then the storage locations, then
/// "No location"), by name or by expiry (P2-08e). A tap opens the product detail; long press offers add stock, add to
/// a list and favourite, never delete (P2-08d).
struct InventoryView: View {
    @Environment(ServiceContainer.self) private var services
    @Environment(SpaceSelection.self) private var selection
    @State private var model: InventoryModel?
    @State private var addingStock = false
    @State private var creatingProduct = false
    @State private var scanning = false
    @State private var router = AppRouter.shared
    @State private var cardActions = ProductCardActions()
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if let model { content(model) } else { ProgressView() }
        }
        .navigationTitle("inventory.title")
        .navigationDestination(for: ProductRoute.self) { ProductDetailView(productID: $0.id) }
        .toolbar { toolbar }
        .task(id: selection.selectedSpaceID) {
            rebuildModel()
            consumeScanRequest()
        }
        .onChange(of: router.scanRequested, initial: true) { consumeScanRequest() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model?.reload() }
        .barcodeFlow(isScanning: $scanning, space: model?.space)
        .productCardActionSheets(cardActions, space: model?.space)
        .sheet(isPresented: $addingStock) {
            if let space = model?.space { StockAddSheet.picking(in: space, services: services) }
        }
        .sheet(isPresented: $creatingProduct) {
            if let space = model?.space {
                ProductFormSheet(model: ProductFormModel(mode: .create(space, barcode: nil), service: services.products))
            }
        }
    }

    @ViewBuilder
    private func content(_ model: InventoryModel) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8, pinnedViews: [.sectionHeaders]) {
                    ForEach(model.sections) { section in
                        Section {
                            ForEach(section.cards.map { SectionCard(section: section.id, card: $0) }) { entry in
                                let card = entry.card
                                NavigationLink(value: ProductRoute(id: card.id)) { ProductCard(card: card) }
                                    .buttonStyle(.plain)
                                    .productCardMenu(card, actions: cardActions, canEdit: model.canEdit)
                                    .accessibilityIdentifier("inventory.row.\(card.name)")
                            }
                        } header: {
                            header(section).id(section.id)
                        }
                    }
                }
                .frame(maxWidth: CardColumn.maxWidth)
                .frame(maxWidth: .infinity)
                .padding(.leading)
                .padding(.trailing, showsIndex(model) ? 28 : 16)
                .padding(.bottom, 24)
            }
            // On the scroll view, not the reader: an identifier on the container would also replace the index's own.
            .accessibilityIdentifier("inventory.grid")
            .overlay(alignment: .trailing) {
                if showsIndex(model) {
                    SectionIndexBar(letters: model.sections.compactMap(\.letter), identifier: "inventory.index") { letter in
                        proxy.scrollTo(InventorySection.Kind.letter(letter), anchor: .top)
                    }
                    .padding(.trailing, 2)
                }
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            BackupReminderBanner(space: model.space)
        }
        .background(Color(uiColor: .systemGroupedBackground))
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
            case .letter(let key):
                Text(verbatim: key)
            case .expiry(let bucket):
                Image(systemName: bucket.symbol).foregroundStyle(bucket.tint)
                Text(bucket.titleKey)
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
        case .letter(let key): "inventory.section.letter.\(key)"
        case .expiry(let bucket): "inventory.section.expiry.\(bucket.identifier)"
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        SpaceSwitcherToolbarItem()
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Section {
                    Picker("inventory.grouping", selection: groupingBinding) {
                        Label("inventory.grouping.location", systemImage: "archivebox").tag(InventoryGrouping.location)
                        Label("inventory.grouping.name", systemImage: "textformat.abc").tag(InventoryGrouping.name)
                        Label("inventory.grouping.expiry", systemImage: "calendar.badge.clock").tag(InventoryGrouping.expiry)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("inventory.grouping")
                }
            } label: {
                Label("inventory.more", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("inventory.more")
            .disabled(model == nil)
        }
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

    /// The grouping lives on the model (remembered per device); the menu shows location until the model exists.
    private var groupingBinding: Binding<InventoryGrouping> {
        Binding(get: { model?.grouping ?? .location }, set: { model?.grouping = $0 })
    }

    /// As on Search: name grouping with at least two letters, and not at accessibility sizes.
    private func showsIndex(_ model: InventoryModel) -> Bool {
        model.showsLetterIndex && !dynamicTypeSize.isAccessibilitySize
    }

    /// The Scan Barcode quick action (N-02) opens the scanner once the model, and so the space, exists.
    private func consumeScanRequest() {
        guard router.scanRequested, model != nil else { return }
        router.scanRequested = false
        scanning = true
    }

    private func rebuildModel() {
        guard let space = services.activeSpace(selectedID: selection.selectedSpaceID) else { return }
        if model?.space == space { model?.reload(); return }
        let fresh = InventoryModel(inventory: services.inventory, storage: services.storageLocations, space: space,
                                   pending: services.pendingDeletions,
                                   preferences: InventoryPreferences(defaults: TabDefaults.store))
        fresh.reload()
        model = fresh
    }
}

/// A product can have a card in several sections (lots in different places). The lazy stack needs ids that are
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

/// The expiry band headers (P2-08e, 3A): the words carry the meaning, the glyph and colour repeat the card's.
private extension ExpiryBucket {
    var titleKey: LocalizedStringKey {
        switch self {
        case .expired: "inventory.section.expired"
        case .today: "inventory.section.today"
        case .soon: "inventory.section.soon"
        case .later: "inventory.section.later"
        case .undated: "inventory.section.noExpiry"
        }
    }

    var symbol: String {
        switch self {
        case .expired: "alarm"
        case .today, .soon: "clock"
        case .later: "calendar"
        case .undated: "calendar.badge.minus"
        }
    }

    var tint: Color {
        switch self {
        case .expired: Palette.expiryCritical
        case .today, .soon: Palette.expirySoon
        case .later, .undated: .secondary
        }
    }

    var identifier: String {
        switch self {
        case .expired: "expired"
        case .today: "today"
        case .soon: "soon"
        case .later: "later"
        case .undated: "undated"
        }
    }
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
