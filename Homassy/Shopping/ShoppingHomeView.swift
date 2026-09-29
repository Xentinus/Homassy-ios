import CoreData
import HomassyCore
import SwiftUI

/// The Shopping tab (P4-03a, the Reminders "All" pattern): every item still to buy as cards, one section per list
/// or per store, and a list filter strip under the title. A tap on a card opens the purchase sheet, long press
/// offers Edit and Delete (undoable), dragging reorders within a list. The "•••" menu manages lists and switches
/// the grouping; `+` adds an item or a list.
struct ShoppingHomeView: View {
    struct Target: Identifiable { let id: UUID }
    struct AddRequest: Identifiable {
        let id = UUID()
        let preselected: UUID?
    }

    let services: ServiceContainer
    @State private var model: ShoppingOverviewModel
    @State private var lists: ShoppingListsModel
    @State private var editing: Target?
    @State private var purchasing: Target?
    @State private var adding: AddRequest?
    @State private var listEditor: ListEditorSheet.Mode?
    @State private var managing = false
    @State private var pendingListDelete: ShoppingListsModel.Summary?
    @Environment(StoreDirectory.self) private var directory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(space: Space, services: ServiceContainer, undoQueue: UndoQueue, directory: StoreDirectory) {
        self.services = services
        _model = State(initialValue: ShoppingOverviewModel(
            service: services.shopping, space: space, undoQueue: undoQueue, pending: services.pendingDeletions,
            preferences: ShoppingHomePreferences(defaults: ShoppingDefaults.store),
            distance: { directory.distance(ofStore: $0) },
            storeTitle: { directory.compactName(ofStore: $0) }))
        _lists = State(initialValue: ShoppingListsModel(service: services.shopping, space: space))
    }

    var body: some View {
        content
            .navigationTitle(Text("shopping.lists.title"))
            .safeAreaBar(edge: .top) {
                if model.showsStrip {
                    ShoppingFilterStrip(chips: model.chips, total: model.totalCount, filter: $model.filter,
                                        edit: { listEditor = .edit($0) },
                                        delete: { id in pendingListDelete = lists.summaries.first { $0.id == id } })
                }
            }
            .toolbar { toolbar }
            .sheet(item: $editing) { target in
                if let item = model.item(for: target.id) {
                    ShoppingItemFormView(item: item, services: services) { reload() }
                }
            }
            .sheet(item: $purchasing, onDismiss: reload) { target in
                if let item = model.item(for: target.id) {
                    PurchaseSheet(item: item, services: services)
                }
            }
            .sheet(item: $adding, onDismiss: reload) { request in
                AddItemSheet(lists: lists.summaries.compactMap { lists.list(for: $0.id) },
                             preselected: request.preselected, services: services)
            }
            .sheet(isPresented: $managing, onDismiss: reload) { ListManagerSheet(model: lists) }
            .sheet(item: $listEditor, onDismiss: reload) { mode in ListEditorSheet(mode: mode, model: lists) }
            .confirmationDialog(Text("shopping.lists.delete.confirm \(pendingListDelete?.name ?? "")"),
                                isPresented: Binding(get: { pendingListDelete != nil },
                                                     set: { if !$0 { pendingListDelete = nil } }),
                                titleVisibility: .visible) {
                Button("shopping.lists.delete.action", role: .destructive) {
                    if let summary = pendingListDelete { lists.delete(summary.id) }
                    pendingListDelete = nil
                    reload()
                }
                Button("common.cancel", role: .cancel) { pendingListDelete = nil }
            }
            .sensoryFeedback(trigger: model.totalCount) { old, new in new < old ? .success : nil }
            .shoppingErrorAlert(model.errorMessage ?? lists.errorMessage) {
                model.dismissError()
                lists.dismissError()
            }
            .task(id: model.grouping) {
                if model.grouping == .store { await directory.refreshLocation() }
            }
            .onAppear { reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: services.context)) { _ in reload() }
    }

    private func reload() {
        model.reload()
        lists.reload()
    }

    // MARK: Toolbar

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        SpaceSwitcherToolbarItem()
        ToolbarItem(placement: .primaryAction) {
            Menu {
                Button { managing = true } label: { Label("shopping.manage", systemImage: "list.bullet") }
                    .accessibilityIdentifier("shopping.manage")
                Section {
                    Picker("shopping.grouping", selection: $model.grouping) {
                        Label("shopping.grouping.list", systemImage: "list.bullet").tag(ShoppingGrouping.list)
                        Label("shopping.grouping.store", systemImage: "storefront").tag(ShoppingGrouping.store)
                    }
                    .pickerStyle(.inline)
                } header: {
                    Text("shopping.grouping")
                }
            } label: {
                Label("shopping.more", systemImage: "ellipsis")
            }
            .accessibilityIdentifier("shopping.more")
            .disabled(!model.hasLists)
        }
        ToolbarItem(placement: .primaryAction) {
            AddMenu {
                Button { adding = AddRequest(preselected: model.filter) } label: {
                    Label("add.shoppingItem", systemImage: "plus.circle")
                }
                .accessibilityIdentifier("addMenu.shoppingItem")
                .disabled(!model.hasLists)
                Button { listEditor = .create } label: { Label("add.shoppingList", systemImage: "list.bullet") }
                    .accessibilityIdentifier("addMenu.shoppingList")
            }
        }
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if !model.hasLists {
            ContentUnavailableView {
                Label("shopping.lists.empty.title", systemImage: "cart")
            } description: {
                Text("shopping.lists.empty.message")
            } actions: {
                Button("shopping.lists.new") { listEditor = .create }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ScrollView {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(model.sections) { section in
                        SwiftUI.Section {
                            ForEach(section.rows) { card($0) }
                        } header: {
                            if showsHeader(section) { header(section) }
                        }
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .overlay {
                if model.sections.isEmpty { emptyItems }
            }
        }
    }

    @ViewBuilder private var emptyItems: some View {
        if model.filter != nil {
            ContentUnavailableView {
                Label("shopping.detail.empty.title", systemImage: "checklist")
            } description: {
                Text("shopping.detail.empty.message")
            } actions: {
                Button("add.shoppingItem") { adding = AddRequest(preselected: model.filter) }
                    .buttonStyle(.borderedProminent)
            }
        } else {
            ContentUnavailableView {
                Label("shopping.home.done.title", systemImage: "checkmark.circle")
            } description: {
                Text("shopping.home.done.message")
            } actions: {
                Button("add.shoppingItem") { adding = AddRequest(preselected: nil) }
                    .buttonStyle(.borderedProminent)
            }
        }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
    }

    private func showsHeader(_ section: ShoppingOverviewModel.Section) -> Bool {
        if case .list = section.kind { return model.showsListHeaders }
        return true
    }

    private func header(_ section: ShoppingOverviewModel.Section) -> some View {
        HStack(spacing: 6) {
            switch section.kind {
            case .list(let chip):
                Circle().fill(ListColor.color(chip.color)).frame(width: 10, height: 10).accessibilityHidden(true)
                Text(verbatim: chip.name)
            case .store(_, let title, _):
                Image(systemName: "storefront").accessibilityHidden(true)
                Text(verbatim: title)
            case .noStore:
                Text("shopping.section.noStore").foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Text(verbatim: countText(section))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .font(.headline)
        .lineLimit(1)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(headerIdentifier(section))
    }

    private func countText(_ section: ShoppingOverviewModel.Section) -> String {
        if case .store(_, _, let distance?) = section.kind {
            return "\(StoreLabel.distanceText(distance)) · \(section.rows.count)"
        }
        return "\(section.rows.count)"
    }

    private func headerIdentifier(_ section: ShoppingOverviewModel.Section) -> String {
        switch section.kind {
        case .list(let chip): "shopping.section.list.\(chip.name)"
        case .store(_, let title, _): "shopping.section.store.\(title)"
        case .noStore: "shopping.section.noStore"
        }
    }

    // MARK: Cards

    /// Long press opens Edit and Delete. Dragging a card onto another card of the same list reorders it, in list
    /// grouping only.
    @ViewBuilder private func card(_ row: ShoppingOverviewModel.Row) -> some View {
        let base = ShoppingItemCard(row: row, showsList: model.grouping == .store) { purchasing = Target(id: row.id) }
            .contextMenu {
                editButton(row)
                deleteButton(row)
            }
            .accessibilityActions {
                editButton(row)
                deleteButton(row)
            }
        if model.canReorder {
            base
                .draggable(row.id.uuidString)
                .dropDestination(for: String.self) { ids, _ in
                    guard let dragged = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
                    withAnimation(reduceMotion ? nil : .snappy) { model.moveItem(dragged, onto: row.id) }
                    return true
                }
        } else {
            base
        }
    }

    private func deleteButton(_ row: ShoppingOverviewModel.Row) -> some View {
        Button(role: .destructive) {
            withAnimation(reduceMotion ? nil : .default) { model.delete(row.id) }
        } label: {
            Label("common.delete", systemImage: "trash")
        }
    }

    private func editButton(_ row: ShoppingOverviewModel.Row) -> some View {
        Button { editing = Target(id: row.id) } label: {
            Label("common.edit", systemImage: "pencil")
        }
    }
}
