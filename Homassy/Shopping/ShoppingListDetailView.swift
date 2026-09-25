import CoreData
import HomassyCore
import SwiftUI

/// One list: a card grid of the items still to buy, by sort order. A tap on a card opens the purchase sheet,
/// long press offers Edit and Delete (undoable), dragging reorders. `+` opens the stepwise add.
/// Bought items leave the list.
struct ShoppingListDetailView: View {
    struct Target: Identifiable { let id: UUID }
    /// Opens the add sheet, carrying what was typed in the quick bar.
    struct AddRequest: Identifiable {
        let id = UUID()
        let query: String
    }

    let list: ShoppingList
    let services: ServiceContainer
    @State private var model: ShoppingListModel
    @State private var editing: Target?
    @State private var purchasing: Target?
    @State private var adding: AddRequest?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(list: ShoppingList, services: ServiceContainer, undoQueue: UndoQueue) {
        self.list = list
        self.services = services
        _model = State(initialValue: ShoppingListModel(service: services.shopping, list: list, undoQueue: undoQueue,
                                                       pending: services.pendingDeletions))
    }

    var body: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.remaining) { row in
                    card(row)
                }
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .overlay {
            if model.totalCount == 0 {
                ContentUnavailableView {
                    Label("shopping.detail.empty.title", systemImage: "checklist")
                } description: {
                    Text("shopping.detail.empty.message")
                }
            }
        }
        .navigationTitle(Text(verbatim: model.listName))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    adding = AddRequest(query: "")
                } label: {
                    Label("shopping.detail.add", systemImage: "plus")
                }
                .accessibilityIdentifier("shopping.detail.add")
            }
        }
        .sheet(item: $editing) { target in
            if let item = model.item(for: target.id) {
                ShoppingItemFormView(item: item, services: services) { model.reload() }
            }
        }
        .sheet(item: $purchasing, onDismiss: { model.reload() }) { target in
            if let item = model.item(for: target.id) {
                PurchaseSheet(item: item, services: services)
            }
        }
        .sheet(item: $adding, onDismiss: { model.reload() }) { request in
            AddItemSheet(list: list, services: services, initialQuery: request.query)
        }
        .sensoryFeedback(trigger: model.totalCount) { old, new in new < old ? .success : nil }
        .shoppingErrorAlert(model.errorMessage) { model.dismissError() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model.reload() }
    }

    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible())]
            : [GridItem(.adaptive(minimum: 160), spacing: 12, alignment: .top)]
    }

    /// Long press opens Edit and Delete; dragging a card onto another reorders.
    private func card(_ row: ShoppingListModel.Row) -> some View {
        ShoppingItemCard(row: row) { purchasing = Target(id: row.id) }
        .contextMenu {
            editButton(row)
            deleteButton(row)
        }
        .accessibilityActions {
            editButton(row)
            deleteButton(row)
        }
        .draggable(row.id.uuidString)
        .dropDestination(for: String.self) { ids, _ in
            guard let dragged = ids.first.flatMap(UUID.init(uuidString:)) else { return false }
            withAnimation(reduceMotion ? nil : .snappy) { model.moveItem(dragged, onto: row.id) }
            return true
        }
    }

    private func deleteButton(_ row: ShoppingListModel.Row) -> some View {
        Button(role: .destructive) {
            withAnimation(reduceMotion ? nil : .default) { model.delete(row.id) }
        } label: {
            Label("common.delete", systemImage: "trash")
        }
    }

    private func editButton(_ row: ShoppingListModel.Row) -> some View {
        Button { editing = Target(id: row.id) } label: {
            Label("common.edit", systemImage: "pencil")
        }
    }
}
