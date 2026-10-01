import CoreData
import HomassyCore
import SwiftUI

/// The product detail (README "Product detail layout", P2-07a): a Contacts-style header with its action row, one stock
/// list sorted by expiry with consume, move and swipe-to-delete, the price trend, the last three history events and
/// the "Adatok" facts. In compact height it splits into the header and facts on the left and the rest on the right.
struct ProductDetailView: View {
    let productID: UUID

    @Environment(ServiceContainer.self) private var services
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: ProductDetailModel?
    @State private var editing = false
    @State private var amountTarget: AmountTarget?
    @State private var editingItem: EditTarget?
    @State private var pendingTransfer: TransferRequest?
    @State private var feedback = 0
    @State private var chartStore: PriceSummary.StoreLine?
    /// Set by the edit form's "Delete product"; the delete runs once the form has closed.
    @State private var deleteRequested = false
    @State private var addingStock = false
    @State private var addingToList = false
    @State private var shoppingLists: [ShoppingList] = []
    @State private var heroNameVisible = true

    /// Which stock item the amount sheet is for, and whether it consumes or moves.
    struct AmountTarget: Identifiable {
        enum Purpose { case consume, move }
        let itemID: UUID
        let purpose: Purpose
        var id: String { "\(itemID)-\(purpose)" }
    }

    struct EditTarget: Identifiable { let id: UUID }

    /// A stock item waiting for the "move to another space" confirmation.
    struct TransferRequest: Identifiable {
        let itemID: UUID
        let target: PickerOption
        var id: String { "\(itemID)-\(target.id)" }
    }

    var body: some View {
        Group {
            if let model, let fields = model.fields {
                content(model, fields: fields)
            } else if model != nil {
                ContentUnavailableView("product.detail.notFound", systemImage: "questionmark.square.dashed")
            } else {
                ProgressView()
            }
        }
        .navigationTitle(model?.fields?.name ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { toolbar }
        .sheet(isPresented: $editing, onDismiss: {
            guard deleteRequested, let model else { return }
            deleteRequested = false
            deleteProduct(model)
        }) {
            if let product = model?.product {
                ProductFormSheet(model: ProductFormModel(mode: .edit(product), service: services.products),
                                 onDelete: { deleteRequested = true })
            }
        }
        .sheet(isPresented: $addingStock) {
            if let space = model?.product.space {
                StockAddSheet.adding(productID, in: space, services: services)
            }
        }
        .sheet(item: $amountTarget) { target in
            if let model, let form = model.amountForm(for: target.itemID) {
                AmountSheet(purpose: target.purpose, form: form,
                            targets: { model.moveTargets(for: target.itemID, matching: $0) }) { amount, location in
                    switch target.purpose {
                    case .consume: perform(model.consume(target.itemID, amount: amount))
                    case .move: perform(model.move(target.itemID, amount: amount, to: location))
                    }
                }
            }
        }
        .sheet(item: $chartStore) { line in
            if let model { PriceChartSheet(model: model, line: line) }
        }
        .sheet(item: $editingItem) { target in
            if let form = model?.editForm(for: target.id, locations: services.shoppingLocations) {
                StockAddSheet(form: form, picker: nil)
            }
        }
        .confirmationDialog("stock.transfer.title", isPresented: Binding(get: { pendingTransfer != nil },
                                                                         set: { if !$0 { pendingTransfer = nil } }),
                            titleVisibility: .visible, presenting: pendingTransfer) { request in
            Button("stock.transfer.confirm \(request.target.name)") {
                if model?.transfer(request.itemID, to: request.target.id) == true {
                    feedback += 1
                    model?.reload()
                }
            }
            .accessibilityIdentifier("stock.transfer.confirm")
            Button("common.cancel", role: .cancel) {}
        }
        .alert("common.error", isPresented: Binding(get: { model?.errorMessage != nil },
                                                    set: { if !$0 { model?.dismissError() } })) {
            Button("common.ok", role: .cancel) {}
        } message: { Text(model?.errorMessage ?? "") }
        .sensoryFeedback(.impact, trigger: feedback)
        .task { load() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in
            model?.reload()
            refreshLists()
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ model: ProductDetailModel, fields: ProductFields) -> some View {
        if verticalSizeClass == .compact {
            HStack(alignment: .top, spacing: 0) {
                List {
                    heroSection(model, fields: fields)
                    ProductFactsSection(fields: fields)
                }
                .frame(maxWidth: .infinity)
                List { activitySections(model) }
                    .frame(maxWidth: .infinity)
            }
            .listStyle(.insetGrouped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("product.detail.split")
        } else {
            List {
                heroSection(model, fields: fields)
                activitySections(model)
                ProductFactsSection(fields: fields)
            }
            .listStyle(.insetGrouped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("product.detail.stack")
        }
    }

    private func heroSection(_ model: ProductDetailModel, fields: ProductFields) -> some View {
        Section {
            ProductHeroHeader(fields: fields, canEdit: model.canEdit, canAddToList: !shoppingLists.isEmpty,
                              toggleFavorite: { model.toggleFavorite() }, addToList: { addingToList = true },
                              nameVisible: { heroNameVisible = $0 })
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let name = model?.fields?.name {
            // The hero shows the name; the bar shows it only once the hero has scrolled away (Contacts).
            ToolbarItem(placement: .principal) {
                Text(verbatim: name)
                    .font(.headline)
                    .lineLimit(1)
                    .opacity(heroNameVisible ? 0 : 1)
                    .accessibilityHidden(heroNameVisible)
                    .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: heroNameVisible)
            }
        }
        if let model, model.canEdit, model.fields != nil {
            // Apple's pattern (HIG, user decision 2026-09-25): Edit is a pencil; Delete sits at the bottom of the
            // edit form. `+` adds stock of this product (P2-07a).
            ToolbarItemGroup(placement: .primaryAction) {
                Button { addingStock = true } label: { Label("stock.title.add", systemImage: "plus") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("product.detail.add")
                Button { editing = true } label: { Label("common.edit", systemImage: "pencil") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("product.detail.edit")
            }
        }
    }

    // MARK: Stock, price trend, history

    @ViewBuilder
    private func activitySections(_ model: ProductDetailModel) -> some View {
        Section {
            if model.stock.isEmpty {
                Text("product.detail.noItems").foregroundStyle(.secondary)
            }
            ForEach(model.stock) { lot in
                StockItemRow(lot: lot, canEdit: model.canEdit, transferTargets: model.transferTargets,
                             consume: { amountTarget = AmountTarget(itemID: lot.id, purpose: .consume) },
                             move: { amountTarget = AmountTarget(itemID: lot.id, purpose: .move) },
                             edit: { editingItem = EditTarget(id: lot.id) },
                             transfer: { pendingTransfer = TransferRequest(itemID: lot.id, target: $0) },
                             delete: { perform(model.deleteItem(lot.id)) })
                    .swipeActions(edge: .trailing) {
                        if model.canEdit {
                            Button(role: .destructive) { perform(model.deleteItem(lot.id)) } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                        }
                    }
            }
        } header: {
            HStack(spacing: 4) {
                Text("product.detail.stockSection")
                Spacer()
                if let total = model.stockTotalText {
                    // One Text, so the separator is not its own (tiny, audited) element.
                    Text(verbatim: "\(total) · \(String(localized: "stock.lot.count \(model.stockCount)"))")
                }
            }
            .monospacedDigit()
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("product.detail.stockHeader")
        }
        Section {
            if model.priceSummary.isEmpty {
                Text("product.detail.noPrices").foregroundStyle(.secondary)
            }
            if let average = model.priceSummary.average {
                VStack(alignment: .leading, spacing: 4) {
                    Text("price.average").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(verbatim: model.unitPriceText(average.unitPrice, currency: average.currency, unit: average.unit))
                        .font(.title.weight(.bold))
                        .fontDesign(.rounded)
                        .monospacedDigit()
                    if let latest = model.latestPrice {
                        Text("price.latest \(model.unitPriceText(latest)) \(latest.date.formatted(.dateTime.month(.abbreviated).day()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("price.average")
                if let trend = model.priceTrend {
                    PriceTrendChart(trend: trend, model: model)
                        .padding(.vertical, 4)
                        .listRowSeparator(.hidden, edges: .top)
                }
            }
            ForEach(model.priceSummary.stores) { line in
                Button { chartStore = line } label: { PriceStoreRow(model: model, line: line) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("price.store.\(line.name ?? "none")")
            }
        } header: {
            HStack {
                Text("product.detail.priceTrend")
                Spacer()
                if model.priceTrend != nil { Text("product.detail.priceWindow") }
            }
        }
        Section("product.detail.historySection") {
            if model.history.isEmpty {
                Text("product.detail.noHistory").foregroundStyle(.secondary)
            }
            ForEach(model.recentHistory) { HistoryEventRow(row: $0) }
            if model.history.count > ProductDetailModel.recentHistoryCount {
                NavigationLink { ProductHistoryView(model: model) } label: {
                    LabeledContent("product.detail.historyAll") {
                        Text(model.history.count, format: .number).monospacedDigit()
                    }
                }
                .accessibilityIdentifier("history.showAll")
            }
        }
    }

    // MARK: Actions

    private func perform(_ action: UndoableAction?) {
        guard let action else { return }
        undoQueue.enqueue(action)
        feedback += 1
        model?.reload()
    }

    private func deleteProduct(_ model: ProductDetailModel) {
        guard let action = model.deleteProduct() else { return }
        undoQueue.enqueue(action)
        feedback += 1
        dismiss()
    }

    private func refreshLists() {
        shoppingLists = model?.product.space.flatMap { try? services.shopping.lists(in: $0) } ?? []
    }

    private func load() {
        guard model == nil else {
            model?.reload()
            refreshLists()
            return
        }
        guard let product = try? services.products.product(publicId: productID) else { return }
        let spaceStore = services.spaceStore
        let fresh = ProductDetailModel(product: product, products: services.products, inventory: services.inventory,
                                       storageLocations: services.storageLocations, pending: services.pendingDeletions,
                                       userRecordName: services.userRecordName,
                                       spaces: { (try? spaceStore.allSpaces()) ?? [] })
        fresh.reload()
        model = fresh
        refreshLists()
    }
}

// MARK: Rows

/// A stock item card. Tapping it opens a menu with consume, move and delete (user choice, 2026-09-24);
/// swiping left deletes.
private struct StockItemRow: View {
    let lot: StockLotRow
    let canEdit: Bool
    let transferTargets: [PickerOption]
    let consume: () -> Void
    let move: () -> Void
    let edit: () -> Void
    let transfer: (PickerOption) -> Void
    let delete: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var item: StockItemCard { lot.card }

    var body: some View {
        Group {
            if canEdit {
                Menu {
                    Button(action: consume) { Label("product.detail.consume", systemImage: "fork.knife") }
                        .accessibilityIdentifier("stock.consume")
                    Button(action: move) { Label("product.detail.move", systemImage: "arrow.right.arrow.left") }
                        .accessibilityIdentifier("stock.move")
                    Button(action: edit) { Label("stock.edit", systemImage: "pencil") }
                        .accessibilityIdentifier("stock.edit")
                    if !transferTargets.isEmpty {
                        Menu {
                            ForEach(transferTargets) { target in
                                Button(target.name) { transfer(target) }
                            }
                        } label: {
                            Label("stock.transfer", systemImage: "house")
                        }
                        .accessibilityIdentifier("stock.transfer")
                    }
                    Divider()
                    Button(role: .destructive, action: delete) { Label("common.delete", systemImage: "trash") }
                        .accessibilityIdentifier("stock.delete")
                } label: {
                    card.contentShape(Rectangle())
                }
                .foregroundStyle(.primary)
            } else {
                card
            }
        }
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
        .accessibilityIdentifier("stock.item")
    }

    /// Quantity and expiry share the first line and the subtitle runs the full width under them, so the purchase
    /// date stays on one line at the default size (a side-by-side subtitle and expiry label do not both fit in 361 pt).
    private var card: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
        return HStack(alignment: .center, spacing: 12) {
            Image(systemName: glyph)
                .foregroundStyle(Palette.mocha600)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                layout {
                    Text(item.quantityText).font(.headline).monospacedDigit()
                    if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 8) }
                    if let expiry = item.expiryText {
                        ExpiryLabel(expiry, level: item.level)
                            .font(.subheadline.weight(.medium))
                    }
                }
                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var glyph: String {
        guard lot.locationName != nil else { return "tray" }
        return lot.isFreezer ? "snowflake" : "archivebox"
    }

    /// "Hűtő · Vásárolva: 2026. szept. 28."
    private var subtitle: String {
        var parts = [lot.locationName ?? String(localized: "product.detail.noLocation")]
        if let purchased = item.purchasedAt {
            parts.append(String(localized: "product.detail.purchased \(purchased.formatted(date: .abbreviated, time: .omitted))"))
        }
        return parts.joined(separator: " · ")
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { ProductDetailView(productID: UUID()) }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { ProductDetailView(productID: UUID()) }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!).environment(model.services!.attribution).environment(model.services!.storeDirectory)
}
#endif
