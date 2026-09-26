#if DEBUG
import HomassyCore
import SwiftUI

/// Shown instead of the Inventory tab root under `-uiTestAccountState … -uiTestUndoDemo`, so UI tests can exercise
/// the undo toast before any real feature enqueues actions. Compiled out of release builds.
/// Uses the card grid from README "Card layout", so it previews the style P2-08 builds for real.
struct UITestUndoDemoView: View {
    @Environment(UndoQueue.self) private var undoQueue
    @State private var items = DemoItem.samples

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 12)], spacing: 12) {
                ForEach(items) { item in
                    // README "Card layout": no delete on the grid; a tap opens the detail, which owns delete.
                    NavigationLink(value: DemoRoute(name: item.name)) {
                        DemoItemCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(16)
        }
        .navigationTitle(AppTab.inventory.title)
        .navigationDestination(for: DemoRoute.self) { route in
            if let item = items.first(where: { $0.name == route.name }) {
                DemoItemDetail(item: item) { delete(item) }
            }
        }
        .toolbar {
            SpaceSwitcherToolbarItem()
        }
    }

    private func delete(_ item: DemoItem) {
        guard let index = items.firstIndex(of: item) else { return }
        items.remove(at: index)
        let binding = $items
        undoQueue.enqueue(UndoableAction(
            title: UndoTitle.removed(item.name),
            kind: .delete,
            revert: { binding.wrappedValue.insert(item, at: min(index, binding.wrappedValue.count)) },
            commit: {}
        ))
    }
}

private struct DemoStock: Identifiable, Hashable {
    let id = UUID()
    var location: String
    var amount: Int
    var unit: String

    static let allLocations = ["Fridge", "Fridge door", "Freezer", "Freezer drawer 2", "Pantry", "Pantry top shelf",
                               "Kitchen cabinet 1", "Kitchen cabinet 2", "Kitchen cabinet 3", "Spice rack",
                               "Basement shelf", "Garage", "Balcony box", "Wine rack", "Bathroom cabinet"]
}

private enum StockAction: Identifiable {
    case consume(DemoStock), move(DemoStock)

    var entry: DemoStock {
        switch self {
        case let .consume(entry), let .move(entry): entry
        }
    }

    var id: String {
        switch self {
        case let .consume(entry): "consume-\(entry.id)"
        case let .move(entry): "move-\(entry.id)"
        }
    }
}

/// Amount capped at what this stock item holds; for a move, a searchable list of every storage location.
private struct StockActionSheet: View {
    let action: StockAction
    let locations: [String]
    let confirm: (Int, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var amount = 1
    @State private var target: String?
    @State private var query = ""

    private var isMove: Bool { if case .move = action { true } else { false } }
    private var maximum: Int { action.entry.amount }
    private var candidates: [String] {
        locations.filter { $0 != action.entry.location && (query.isEmpty || $0.localizedCaseInsensitiveContains(query)) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Stepper(value: $amount, in: 1...maximum) {
                        Text(verbatim: "\(amount) of \(maximum) \(action.entry.unit)").monospacedDigit()
                    }
                } header: {
                    Text(verbatim: "Amount · from \(action.entry.location)")
                } footer: {
                    Text(verbatim: "At most \(maximum) \(action.entry.unit), what this location holds.")
                }
                if isMove {
                    Section {
                        TextField(text: $query) { Text(verbatim: "Search storage locations") }
                            .textInputAutocapitalization(.never)
                        ForEach(candidates, id: \.self) { location in
                            Button {
                                target = location
                            } label: {
                                HStack {
                                    Text(verbatim: location).foregroundStyle(.primary)
                                    Spacer()
                                    if target == location { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                                }
                            }
                        }
                    } header: {
                        Text(verbatim: "Move to")
                    }
                }
            }
            .navigationTitle(Text(verbatim: isMove ? "Move" : "Consume"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button { confirm(amount, target); dismiss() } label: {
                        Text(verbatim: isMove ? "Move" : "Consume")
                    }
                    .disabled(amount < 1 || amount > maximum || (isMove && target == nil))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct DemoEvent: Identifiable {
    let id = UUID()
    let symbol: String
    let title: String
    let detail: String
}

/// Deliberately not Codable, so the demo never lands in the restored navigation path.
private struct DemoRoute: Hashable {
    let name: String
}

private struct DemoItem: Identifiable, Hashable {
    enum Expiry: Hashable { case none, later(String), soon(String), expired(String) }

    let name: String
    let brand: String?
    let barcode: String?
    let category: String?
    let quantity: String
    let symbol: String
    let expiry: Expiry
    var prices: [String] = []
    var stock: [DemoStock] = [DemoStock(location: "Fridge", amount: 1, unit: "pc")]

    var id: String { name }

    static let samples = [
        DemoItem(name: "Milk", brand: "Mizo", barcode: "5998200101234", category: "Dairy", quantity: "2 × 1 l",
                 symbol: "waterbottle", expiry: .expired("Expired yesterday"),
                 prices: ["Sep 20 · Spar · 429 Ft", "Sep 6 · Aldi · 399 Ft", "Aug 23 · Spar · 449 Ft"]),
        DemoItem(name: "Bread", brand: "Fornetti", barcode: nil, category: "Bakery", quantity: "1 pc",
                 symbol: "birthday.cake", expiry: .soon("9 days left")),
        DemoItem(name: "Eggs", brand: nil, barcode: nil, category: "Dairy", quantity: "10 pcs",
                 symbol: "oval.portrait", expiry: .later("3 weeks left"),
                 stock: [DemoStock(location: "Fridge", amount: 10, unit: "pcs"), DemoStock(location: "Pantry", amount: 2, unit: "pcs")]),
        DemoItem(name: "Basmati rice", brand: "Tilda", barcode: "5011157630016", category: "Grains", quantity: "1 × 2 kg",
                 symbol: "leaf", expiry: .later("8 months left"), prices: ["Jul 2 · Lidl · 1 290 Ft"]),
        DemoItem(name: "Aspirin", brand: "Bayer", barcode: "5993300417911", category: "Medicine", quantity: "1 box",
                 symbol: "pills", expiry: .none),
        DemoItem(name: "Butter", brand: "Pöttyös", barcode: nil, category: "Dairy", quantity: "1 × 250 g",
                 symbol: "square.stack", expiry: .soon("12 days left")),
    ]
}

private struct DemoItemCard: View {
    let item: DemoItem

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: item.symbol)
                .font(.title2)
                .foregroundStyle(Palette.mocha700)
                .frame(maxWidth: .infinity, minHeight: 72)
                .background(Palette.mocha50, in: .rect(cornerRadius: 12))
                .accessibilityHidden(true)
                .padding(.bottom, 4)

            Text(verbatim: item.name)
                .font(.headline)
                .lineLimit(2)
            if let brand = item.brand {
                Text(verbatim: brand)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            if let barcode = item.barcode {
                Label { Text(verbatim: barcode).monospacedDigit() } icon: { Image(systemName: "barcode") }
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Label { Text(verbatim: item.quantity) } icon: { Image(systemName: "shippingbox") }
                    .font(.subheadline.weight(.medium))
            }
            expiryLine
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(background, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16).strokeBorder(border, lineWidth: tint == nil ? 1 : 1.5)
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var expiryLine: some View {
        switch item.expiry {
        case .none:
            EmptyView()
        case let .later(text):
            Label { Text(verbatim: text) } icon: { Image(systemName: "calendar") }
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        case let .soon(text):
            Label { Text(verbatim: text) } icon: { Image(systemName: "clock") }
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.expirySoon)
        case let .expired(text):
            Label { Text(verbatim: text) } icon: { Image(systemName: "alarm") }
                .font(.caption.weight(.medium))
                .foregroundStyle(Palette.expiryCritical)
        }
    }

    /// README "Card layout": yellow within 14 days, red only once expired, neutral otherwise.
    private var tint: Color? {
        switch item.expiry {
        case .soon: Palette.expirySoon
        case .expired: Palette.expiryCritical
        case .none, .later: nil
        }
    }

    private var background: Color { tint.map { $0.opacity(0.08) } ?? Color(.secondarySystemGroupedBackground) }
    private var border: Color { tint.map { $0.opacity(0.7) } ?? Color(.separator) }
}

/// Stand-in for the P2-07 product detail (README "Card layout" → "Product detail layout"):
/// header card with chips, stock items, price trend, history. Deleting the product lives only here.
private struct DemoItemDetail: View {
    let item: DemoItem
    let delete: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isFavorite = false
    @State private var stock: [DemoStock] = []
    @State private var history: [DemoEvent] = []
    @State private var action: StockAction?
    @Environment(UndoQueue.self) private var undoQueue

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header
                section(title: "In stock", systemImage: "shippingbox", count: stock.count) {
                    ForEach(stock) { entry in
                        DetailCard {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Label { Text(verbatim: "\(entry.amount) \(entry.unit)").font(.title3.weight(.semibold)) } icon: {
                                        Image(systemName: "shippingbox").foregroundStyle(Palette.mocha600)
                                    }
                                    Label { Text(verbatim: entry.location) } icon: {
                                        Image(systemName: entry.location.contains("Fridge") ? "refrigerator" : "cabinet")
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Menu {
                                    Button { action = .consume(entry) } label: {
                                        Label { Text(verbatim: "Consume…") } icon: { Image(systemName: "fork.knife") }
                                    }
                                    Button { action = .move(entry) } label: {
                                        Label { Text(verbatim: "Move…") } icon: { Image(systemName: "arrow.right.arrow.left") }
                                    }
                                    Button(role: .destructive) { remove(entry) } label: {
                                        Label { Text(verbatim: "Remove stock item") } icon: { Image(systemName: "trash") }
                                    }
                                } label: {
                                    Image(systemName: "ellipsis.circle").font(.title3).foregroundStyle(Palette.mocha600)
                                }
                                .accessibilityLabel(Text(verbatim: "Stock actions"))
                            }
                        }
                    }
                }
                section(title: "Price trend", systemImage: "chart.line.uptrend.xyaxis", count: nil) {
                    DetailCard {
                        if item.prices.isEmpty {
                            Text(verbatim: "No purchase with a price yet.").foregroundStyle(.secondary)
                        } else {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(item.prices, id: \.self) { Text(verbatim: $0) }
                            }
                        }
                    }
                }
                section(title: "History", systemImage: "clock.arrow.circlepath", count: history.count) {
                    DetailCard {
                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(history) { event in
                                HStack(alignment: .top, spacing: 12) {
                                    Image(systemName: event.symbol).foregroundStyle(Palette.mocha600).frame(width: 22)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(verbatim: event.title).font(.headline)
                                        HStack(spacing: 6) {
                                            Text(verbatim: event.detail)
                                            Circle().fill(Color.memberAccent(seed: "_localDeveloper")).frame(width: 8, height: 8)
                                            Text(verbatim: "You")
                                        }
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(verbatim: "Today").font(.subheadline).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(Text(verbatim: item.name))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $action) { action in
            StockActionSheet(action: action, locations: DemoStock.allLocations) { amount, target in
                switch action {
                case let .consume(entry): consume(entry, amount: amount)
                case let .move(entry): if let target { move(entry, amount: amount, to: target) }
                }
            }
        }
        .onAppear {
            guard stock.isEmpty, history.isEmpty else { return }
            stock = item.stock
            history = item.stock.map { DemoEvent(symbol: "plus.circle", title: "Added", detail: "\($0.amount) \($0.unit) · \($0.location)") }
        }
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    dismiss()
                    delete()
                } label: {
                    Label("common.delete", systemImage: "trash")
                }
            }
        }
    }

    /// Applies a change now and offers it in the undo toast (README: consume, move and delete are undoable).
    private func undoable(_ title: String, kind: UndoKind, _ change: () -> Void) {
        let (stockBefore, historyBefore) = (stock, history)
        change()
        let (stockBinding, historyBinding) = ($stock, $history)
        undoQueue.enqueue(UndoableAction(title: title, kind: kind,
                                         revert: { stockBinding.wrappedValue = stockBefore; historyBinding.wrappedValue = historyBefore },
                                         commit: {}))
    }

    private func consume(_ entry: DemoStock, amount: Int) {
        undoable(UndoTitle.consumed("\(amount) \(entry.unit) \(item.name)"), kind: .consume) { applyConsume(entry, amount: amount) }
    }

    private func move(_ entry: DemoStock, amount: Int, to target: String) {
        undoable(UndoTitle.moved("\(amount) \(entry.unit) \(item.name)"), kind: .move) { applyMove(entry, amount: amount, to: target) }
    }

    private func remove(_ entry: DemoStock) {
        undoable(UndoTitle.removed("\(entry.amount) \(entry.unit) \(item.name)"), kind: .delete) { applyRemove(entry) }
    }

    private func applyConsume(_ entry: DemoStock, amount: Int) {
        guard let index = stock.firstIndex(where: { $0.id == entry.id }), amount <= stock[index].amount else { return }
        stock[index].amount -= amount
        history.insert(DemoEvent(symbol: "fork.knife", title: "Consumed", detail: "\(amount) \(entry.unit) · \(entry.location)"), at: 0)
        if stock[index].amount <= 0 { stock.remove(at: index) }
    }

    private func applyMove(_ entry: DemoStock, amount: Int, to target: String) {
        guard let index = stock.firstIndex(where: { $0.id == entry.id }), amount <= stock[index].amount else { return }
        stock[index].amount -= amount
        if let existing = stock.firstIndex(where: { $0.location == target }) {
            stock[existing].amount += amount
        } else {
            stock.append(DemoStock(location: target, amount: amount, unit: entry.unit))
        }
        if stock[index].amount <= 0 { stock.remove(at: index) }
        history.insert(DemoEvent(symbol: "arrow.right.arrow.left", title: "Moved",
                                 detail: "\(amount) \(entry.unit) · \(entry.location) → \(target)"), at: 0)
    }

    private func applyRemove(_ entry: DemoStock) {
        stock.removeAll { $0.id == entry.id }
        history.insert(DemoEvent(symbol: "trash", title: "Removed", detail: "\(entry.amount) \(entry.unit) · \(entry.location)"), at: 0)
    }

    private var header: some View {
        DetailCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 14) {
                    Image(systemName: item.symbol)
                        .font(.title)
                        .foregroundStyle(Palette.mocha700)
                        .frame(width: 64, height: 64)
                        .background(Palette.mocha50, in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(verbatim: item.name).font(.title2.weight(.semibold))
                        if let brand = item.brand { Text(verbatim: brand).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button { isFavorite.toggle() } label: {
                        Image(systemName: isFavorite ? "heart.fill" : "heart")
                            .font(.title3)
                            .foregroundStyle(Palette.accent)
                    }
                    .accessibilityLabel(Text(verbatim: "Favourite"))
                }
                Divider()
                FlowChips(chips: chips)
            }
        }
    }

    private var chips: [(String, String)] {
        var chips = [("scalemass", item.quantity.components(separatedBy: " ").last ?? "")]
        if let category = item.category { chips.append(("tag", category)) }
        if let barcode = item.barcode { chips.append(("barcode", barcode)) }
        return chips
    }

    private func section<Content: View>(title: String, systemImage: String, count: Int?,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: systemImage).foregroundStyle(Palette.mocha600)
                Text(verbatim: title).font(.title3.weight(.semibold))
                if let count {
                    Text(verbatim: "\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Palette.mocha100, in: .capsule)
                }
            }
            content()
        }
    }
}

private struct DetailCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1) }
    }
}

private struct FlowChips: View {
    let chips: [(String, String)]

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { chipViews }
            VStack(alignment: .leading, spacing: 8) { chipViews }
        }
    }

    @ViewBuilder
    private var chipViews: some View {
        ForEach(chips, id: \.1) { symbol, text in
            Label { Text(verbatim: text).monospacedDigit() } icon: { Image(systemName: symbol) }
                .font(.subheadline)
                .padding(.horizontal, 10).padding(.vertical, 6)
                .overlay { Capsule().strokeBorder(Color(.separator), lineWidth: 1) }
        }
    }
}
#endif
