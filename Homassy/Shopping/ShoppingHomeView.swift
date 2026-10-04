import CoreData
import HomassyCore
import SwiftUI

/// The Shopping tab (P4-03a, the Reminders "All" pattern): every item still to buy as wide cards in one column
/// (P2-08d), one section per list, per store or per initial letter (with a letter index, P2-08e), and a list filter
/// strip under the title. A tap on a card opens the purchase sheet; swipe left deletes and swipe right edits, long
/// press offers both (undoable); dragging reorders within a list. The "•••" menu manages lists and switches the grouping; `+` adds an item or a list.
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
    @State private var router = AppRouter.shared
    @State private var listWidth: CGFloat = 0
    @Environment(StoreDirectory.self) private var directory
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(space: Space, services: ServiceContainer, undoQueue: UndoQueue, directory: StoreDirectory) {
        self.services = services
        _model = State(initialValue: ShoppingOverviewModel(
            service: services.shopping, space: space, undoQueue: undoQueue, pending: services.pendingDeletions,
            preferences: ShoppingHomePreferences(defaults: TabDefaults.store),
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
            .onChange(of: router.shoppingRequest, initial: true) { consumeShoppingRequest() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: services.context)) { _ in reload() }
    }

    private func reload() {
        model.reload()
        lists.reload()
    }

    /// A quick action (N-02) filters to its list or opens the add sheet preset to it; a Live Activity tap (N-04) shows
    /// every list grouped by store. Only the home of the request's space takes it: the home of the previous space may
    /// still be on screen while the space switches.
    private func consumeShoppingRequest() {
        guard let request = router.shoppingRequest, request.spaceID == model.space.publicId else { return }
        router.shoppingRequest = nil
        if request.byStore {
            model.filter = nil
            model.grouping = .store          // nearest store first: the one the activity is about is on top
        } else if request.adds {
            adding = AddRequest(preselected: request.listID)
        } else {
            model.filter = request.listID
        }
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
                        Label("shopping.grouping.name", systemImage: "textformat.abc").tag(ShoppingGrouping.name)
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
            ScrollViewReader { proxy in
                List {
                    ForEach(model.sections) { section in
                        SwiftUI.Section {
                            ForEach(section.rows) { card($0) }
                                .onMove(perform: model.canReorder ? { source, destination in
                                    withAnimation(reduceMotion ? nil : .snappy) {
                                        _ = model.move(fromOffsets: source, toOffset: destination, in: section)
                                    }
                                } : nil)
                        } header: {
                            if showsHeader(section) { header(section) }
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
                .onGeometryChange(for: CGFloat.self) { $0.size.width + $0.safeAreaInsets.leading + $0.safeAreaInsets.trailing } action: { listWidth = $0 }
                .contentMargins(.leading, columnInset, for: .scrollContent)
                .contentMargins(.trailing, trailingInset, for: .scrollContent)
                .overlay {
                    if model.sections.isEmpty { emptyItems }
                }
                .overlay(alignment: .trailing) {
                    if showsIndex {
                        // A List does not scroll to a header id, so a letter scrolls to its first row (as the picker does).
                        SectionIndexBar(letters: model.sections.compactMap(\.letter), identifier: "shopping.index") { letter in
                            if let first = model.sections.first(where: { $0.letter == letter })?.rows.first {
                                proxy.scrollTo(first.id, anchor: .top)
                            }
                        }
                        .padding(.trailing, 2)
                    }
                }
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

    /// The space left and right of the card column: 16 pt, or more once the screen is wider than the column. The
    /// scroll content margins count from the screen edge, so the width includes the safe area.
    private var columnInset: CGFloat { max(16, (listWidth - CardColumn.maxWidth) / 2) }

    /// As on Search: name grouping with at least two letters, and not at accessibility sizes.
    private var showsIndex: Bool { model.showsLetterIndex && !dynamicTypeSize.isAccessibilitySize }

    /// The letter index needs 28 pt on the trailing side.
    private var trailingInset: CGFloat { showsIndex ? max(columnInset, 28) : columnInset }

    private func showsHeader(_ section: ShoppingOverviewModel.Section) -> Bool {
        if case .list = section.kind { return model.showsListHeaders }
        return true
    }

    /// One line at normal sizes; at accessibility sizes the count and distance go under the title and the title wraps.
    @ViewBuilder private func header(_ section: ShoppingOverviewModel.Section) -> some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        Group {
            if stacked {
                VStack(alignment: .leading, spacing: 2) {
                    headerTitle(section)
                    headerCount(section)
                }
            } else {
                HStack(spacing: 6) {
                    headerTitle(section).lineLimit(1)
                    Spacer(minLength: 8)
                    headerCount(section).lineLimit(1)
                }
            }
        }
        .font(.headline)
        .foregroundStyle(.primary)          // a plain-list header would otherwise dim the title and the count
        .padding(.top, 8)
        .padding(.leading, columnInset)
        .padding(.trailing, trailingInset)
        .listRowInsets(EdgeInsets())
        .textCase(nil)
        .background(Color(uiColor: .systemGroupedBackground))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: headerSpokenText(section)))
        .accessibilityAddTraits(.isHeader)
        .accessibilityIdentifier(headerIdentifier(section))
    }

    private func headerTitle(_ section: ShoppingOverviewModel.Section) -> some View {
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
            case .letter(let key):
                Text(verbatim: key)
            }
        }
    }

    private func headerCount(_ section: ShoppingOverviewModel.Section) -> some View {
        Text(verbatim: countText(section))
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .monospacedDigit()
    }

    private func countText(_ section: ShoppingOverviewModel.Section) -> String {
        if case .store(_, _, let distance?) = section.kind {
            return "\(StoreLabel.distanceText(distance)) · \(section.rows.count)"
        }
        return "\(section.rows.count)"
    }

    /// "Weekly, 3 to buy" / "Auchan · Budaörs, 1,2 km, 3 to buy" instead of the bare numbers.
    private func headerSpokenText(_ section: ShoppingOverviewModel.Section) -> String {
        var parts: [String]
        switch section.kind {
        case .list(let chip): parts = [chip.name]
        case .store(_, let title, let distance):
            parts = [title]
            if let distance { parts.append(StoreLabel.distanceText(distance)) }
        case .noStore: parts = [String(localized: "shopping.section.noStore")]
        case .letter(let key): parts = [key]
        }
        parts.append(String(localized: "shopping.lists.remaining \(section.rows.count)"))
        return parts.joined(separator: ", ")
    }

    private func headerIdentifier(_ section: ShoppingOverviewModel.Section) -> String {
        switch section.kind {
        case .list(let chip): "shopping.section.list.\(chip.name)"
        case .store(_, let title, _): "shopping.section.store.\(title)"
        case .noStore: "shopping.section.noStore"
        case .letter(let key): "shopping.section.letter.\(key)"
        }
    }

    // MARK: Cards

    /// A tap opens the purchase sheet. Swipe left deletes (a full swipe at once, undoable), swipe right edits, long
    /// press offers both (user pick 4B, the Reminders / Mail pattern). Dragging reorders within a list, in list
    /// grouping only. The swipe actions already reach VoiceOver as custom actions, so there is no separate set.
    @ViewBuilder private func card(_ row: ShoppingOverviewModel.Row) -> some View {
        ShoppingItemCard(row: row, showsList: model.grouping == .store) { purchasing = Target(id: row.id) }
            .contextMenu {
                editButton(row)
                deleteButton(row)
            }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(row) }
            .swipeActions(edge: .leading) { editButton(row).tint(.gray) }
            .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 4, trailing: 0))
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
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
