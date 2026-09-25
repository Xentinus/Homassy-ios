import CoreData
import HomassyCore
import SwiftUI

/// One list: the items still to buy by sort order, with the quick add bar at the bottom. Each item is a card:
/// the checkbox buys the whole quantity into inventory (undoable), a tap on the card opens the purchase sheet,
/// swipe left deletes (undoable), swipe right edits, drag reorders. Bought items leave the list.
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
    @State private var boughtCount = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(list: ShoppingList, services: ServiceContainer, undoQueue: UndoQueue) {
        self.list = list
        self.services = services
        _model = State(initialValue: ShoppingListModel(service: services.shopping, inventory: services.inventory,
                                                       list: list, undoQueue: undoQueue,
                                                       pending: services.pendingDeletions))
    }

    var body: some View {
        List {
            Section {
                ForEach(model.remaining) { row in
                    card(row)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(row) }
                        .swipeActions(edge: .leading) { editButton(row) }
                }
                .onMove { model.moveRemaining(fromOffsets: $0, toOffset: $1) }
            } header: {
                if !model.remaining.isEmpty { Text("shopping.detail.toBuy") }
            }
        }
        .listRowSpacing(8)
        .overlay {
            if model.totalCount == 0 {
                ContentUnavailableView {
                    Label("shopping.detail.empty.title", systemImage: "checklist")
                } description: {
                    Text("shopping.detail.empty.message")
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            AddItemBar(model: model) {
                adding = AddRequest(query: model.draftText)
                model.draftText = ""
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
        .sensoryFeedback(.success, trigger: boughtCount)
        .shoppingErrorAlert(model.errorMessage) { model.dismissError() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model.reload() }
    }

    private func card(_ row: ShoppingListModel.Row) -> some View {
        HStack(spacing: 4) {
            ShoppingItemCheckbox(row: row) {
                withAnimation(reduceMotion ? nil : .snappy) { model.quickPurchase(row.id) }
                boughtCount += 1
            }
            Button { purchasing = Target(id: row.id) } label: { ShoppingItemCardContent(row: row) }
                .buttonStyle(.plain)
                .accessibilityHint(Text("shopping.item.openPurchaseHint"))
                .accessibilityIdentifier("shopping.item.\(row.name)")
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 16))
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
        .tint(.accentColor)
    }
}
