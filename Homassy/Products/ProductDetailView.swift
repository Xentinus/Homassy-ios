import CoreData
import HomassyCore
import SwiftUI

/// The product detail (README "Product detail layout"): a header card, the stock by storage location with
/// consume, move and swipe-to-delete, the price trend and the history. In compact height it splits into
/// the header on the left and the rest on the right.
struct ProductDetailView: View {
    let productID: UUID

    @Environment(ServiceContainer.self) private var services
    @Environment(UndoQueue.self) private var undoQueue
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dismiss) private var dismiss
    @State private var model: ProductDetailModel?
    @State private var editing = false
    @State private var amountTarget: AmountTarget?
    @State private var editingItem: EditTarget?
    @State private var pendingTransfer: TransferRequest?
    @State private var feedback = 0
    @State private var chartStore: PriceSummary.StoreLine?

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
        .sheet(isPresented: $editing) {
            if let product = model?.product {
                ProductFormSheet(model: ProductFormModel(mode: .edit(product), service: services.products))
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
            if let form = model?.editForm(for: target.id) {
                StockFormSheet(model: form)
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
                                                        object: services.context)) { _ in model?.reload() }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ model: ProductDetailModel, fields: ProductFields) -> some View {
        if verticalSizeClass == .compact {
            HStack(alignment: .top, spacing: 0) {
                List { headerSection(model, fields: fields) }
                    .frame(maxWidth: .infinity)
                List { activitySections(model) }
                    .frame(maxWidth: .infinity)
            }
            .listStyle(.insetGrouped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("product.detail.split")
        } else {
            List {
                headerSection(model, fields: fields)
                activitySections(model)
            }
            .listStyle(.insetGrouped)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("product.detail.stack")
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let model, model.canEdit, model.fields != nil {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = true } label: { Label("common.edit", systemImage: "pencil") }
                    .labelStyle(.iconOnly)
                    .accessibilityIdentifier("product.detail.edit")
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { deleteProduct(model) } label: {
                        Label("product.detail.deleteProduct", systemImage: "trash")
                    }
                    .accessibilityIdentifier("product.detail.delete")
                } label: {
                    Label("product.detail.more", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("product.detail.menu")
            }
        }
    }

    // MARK: Header card

    private func headerSection(_ model: ProductDetailModel, fields: ProductFields) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ProductImageView(data: fields.image, size: 88)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(fields.name).font(.title2.bold())
                        if let brand = fields.brand {
                            Text(brand).foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    Button { model.toggleFavorite() } label: {
                        Image(systemName: fields.isFavorite ? "heart.fill" : "heart")
                            .font(.title2)
                            .foregroundStyle(Palette.accent)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .disabled(!model.canEdit)
                    .accessibilityLabel(Text("product.field.favorite"))
                    .accessibilityValue(Text(fields.isFavorite ? "common.yes" : "common.no"))
                    .accessibilityIdentifier("product.detail.favorite")
                }
                ChipsLayout(spacing: 8) {
                    Chip(text: Text(fields.unitName), systemImage: "scalemass")
                    if let category = fields.category {
                        Chip(text: Text(category), systemImage: "tag")
                    }
                    if let barcode = fields.barcode {
                        Chip(text: Text(barcode).monospacedDigit(), systemImage: "barcode")
                    }
                }
                if let url = fields.url {
                    Link(destination: url) {
                        Label(url.host() ?? url.absoluteString, systemImage: "link")
                            .font(.callout)
                            .lineLimit(1)
                    }
                    .accessibilityIdentifier("product.detail.link")
                }
                if let notes = fields.notes {
                    Text(notes).font(.callout).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // MARK: Stock, price trend, history

    @ViewBuilder
    private func activitySections(_ model: ProductDetailModel) -> some View {
        Section {
            if model.stockGroups.isEmpty {
                Text("product.detail.noItems").foregroundStyle(.secondary)
            }
        } header: {
            Text("product.detail.stock \(model.stockCount)")
        }
        ForEach(model.stockGroups) { group in
            Section {
                ForEach(group.items) { item in
                    StockItemRow(item: item, canEdit: model.canEdit, transferTargets: model.transferTargets,
                                 consume: { amountTarget = AmountTarget(itemID: item.id, purpose: .consume) },
                                 move: { amountTarget = AmountTarget(itemID: item.id, purpose: .move) },
                                 edit: { editingItem = EditTarget(id: item.id) },
                                 transfer: { pendingTransfer = TransferRequest(itemID: item.id, target: $0) },
                                 delete: { perform(model.deleteItem(item.id)) })
                        .swipeActions(edge: .trailing) {
                            if model.canEdit {
                                Button(role: .destructive) { perform(model.deleteItem(item.id)) } label: {
                                    Label("common.delete", systemImage: "trash")
                                }
                            }
                        }
                }
            } header: {
                HStack {
                    Label { group.name.map { Text($0) } ?? Text("product.detail.noLocation") } icon: {
                        Image(systemName: "archivebox")
                    }
                    Spacer()
                    Text(group.totalText).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("stock.group.\(group.name ?? "none")")
            }
        }
        Section("product.detail.priceTrend") {
            if model.priceSummary.isEmpty {
                Text("product.detail.noPrices").foregroundStyle(.secondary)
            }
            if let average = model.priceSummary.average {
                LabeledContent("price.average") {
                    Text(verbatim: model.unitPriceText(average.unitPrice, currency: average.currency, unit: average.unit))
                        .font(.body.weight(.semibold))
                        .monospacedDigit()
                }
                .accessibilityIdentifier("price.average")
            }
            ForEach(model.priceSummary.stores) { line in
                Button { chartStore = line } label: { PriceStoreRow(model: model, line: line) }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("price.store.\(line.name ?? "none")")
            }
        }
        Section {
            if model.history.isEmpty {
                Text("product.detail.noHistory").foregroundStyle(.secondary)
            }
            ForEach(model.history) { HistoryEventRow(row: $0) }
        } header: {
            Text("product.detail.history \(model.history.count)")
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

    private func load() {
        guard model == nil else { model?.reload(); return }
        guard let product = try? services.products.product(publicId: productID) else { return }
        let spaceStore = services.spaceStore
        let fresh = ProductDetailModel(product: product, products: services.products, inventory: services.inventory,
                                       storageLocations: services.storageLocations, pending: services.pendingDeletions,
                                       userRecordName: services.userRecordName,
                                       spaces: { (try? spaceStore.allSpaces()) ?? [] })
        fresh.reload()
        model = fresh
    }
}

// MARK: Rows

/// A stock item card. Tapping it opens a menu with consume, move and delete (user choice, 2026-09-24);
/// swiping left deletes.
private struct StockItemRow: View {
    let item: StockItemCard
    let canEdit: Bool
    let transferTargets: [PickerOption]
    let consume: () -> Void
    let move: () -> Void
    let edit: () -> Void
    let transfer: (PickerOption) -> Void
    let delete: () -> Void

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
        .listRowBackground(Color(uiColor: .secondarySystemGroupedBackground).overlay(item.level.cardWash))
        .accessibilityIdentifier("stock.item")
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.quantityText).font(.headline).monospacedDigit()
                Spacer()
                if let expiry = item.expiryText {
                    Label(expiry, systemImage: item.level.cardGlyph)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(item.level.cardForeground)
                }
            }
            if let purchased = item.purchasedAt {
                Text("product.detail.purchased \(purchased.formatted(date: .abbreviated, time: .omitted))")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct HistoryEventRow: View {
    let row: HistoryRow

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: row.kind.glyph)
                .foregroundStyle(Palette.mocha600)
                .frame(width: 24)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline) {
                    Text(row.kind.title)
                    Text(row.quantityText).monospacedDigit().foregroundStyle(.secondary)
                }
                if let places = placesText {
                    Text(places).font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.memberAccent(seed: row.actorSeed))
                        .frame(width: 8, height: 8)
                        .accessibilityHidden(true)
                    actorText.font(.caption)
                    if let date = row.occurredAt {
                        Text(date, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var actorText: Text {
        if row.isCurrentUser { return Text("history.actor.you") }
        if let name = row.actorName { return Text(name) }
        return Text("history.actor.someone")
    }

    private var placesText: String? {
        switch (row.fromLocation, row.toLocation) {
        case let (from?, to?): "\(from) → \(to)"
        case let (from?, nil): from
        case let (nil, to?): "→ \(to)"
        case (nil, nil): nil
        }
    }
}

private extension InventoryEventKind {
    var title: LocalizedStringKey {
        switch self {
        case .added: "history.kind.added"
        case .consumed: "history.kind.consumed"
        case .moved: "history.kind.moved"
        case .deleted: "history.kind.deleted"
        case .edited: "history.kind.edited"
        }
    }

    var glyph: String {
        switch self {
        case .added: "plus.circle"
        case .consumed: "fork.knife"
        case .moved: "arrow.right.arrow.left"
        case .deleted: "trash"
        case .edited: "pencil"
        }
    }
}

private struct Chip: View {
    let text: Text
    let systemImage: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: systemImage).accessibilityHidden(true)
            text.lineLimit(1)
        }
            .font(.caption.weight(.medium))
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Palette.mocha500.opacity(0.15), in: Capsule())
            .foregroundStyle(.primary)
            .fixedSize()
            .accessibilityElement(children: .combine)
    }
}

/// Lays chips out left to right, wrapping onto new lines.
struct ChipsLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.last.map { $0.y + $0.height } ?? 0
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: .unspecified)
                x += size.width + spacing
            }
        }
    }

    private struct Row { var indices: [Int] = []; var y: CGFloat = 0; var width: CGFloat = 0; var height: CGFloat = 0 }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row(y: current.y + current.height + spacing)
            }
            current.width = current.indices.isEmpty ? size.width : current.width + spacing + size.width
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}

#if DEBUG
#Preview("Portrait") {
    let model = AppModel.preview()
    NavigationStack { ProductDetailView(productID: UUID()) }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    NavigationStack { ProductDetailView(productID: UUID()) }
        .environment(model).environment(model.selection).environment(model.undoQueue)
        .environment(model.services!)
}
#endif
