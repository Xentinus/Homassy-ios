import CoreData
import HomassyCore
import SwiftUI

/// One list: items to buy by sort order, then a collapsible "Bought" section, with the add bar at the bottom.
/// Each item is a card: the checkbox marks it bought (undoable), a tap on the card opens the product detail
/// (or the item form for a custom item), swipe left deletes (undoable), swipe right edits, drag reorders.
struct ShoppingListDetailView: View {
    struct EditTarget: Identifiable { let id: UUID }

    let services: ServiceContainer
    @State private var model: ShoppingListModel
    @State private var editing: EditTarget?
    @State private var confirmClear = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(list: ShoppingList, services: ServiceContainer, undoQueue: UndoQueue) {
        self.services = services
        _model = State(initialValue: ShoppingListModel(service: services.shopping, list: list,
                                                       undoQueue: undoQueue, pending: services.pendingDeletions))
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

            if !model.purchased.isEmpty {
                Section {
                    if model.showPurchased {
                        ForEach(model.purchased) { row in
                            card(row)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) { deleteButton(row) }
                                .swipeActions(edge: .leading) { editButton(row) }
                        }
                    }
                } header: {
                    purchasedHeader
                }
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
        .safeAreaInset(edge: .bottom) { AddItemBar(model: model) }
        .navigationTitle(Text(verbatim: model.listName))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button(role: .destructive) { confirmClear = true } label: {
                        Label("shopping.detail.clearPurchased", systemImage: "checkmark.circle.badge.xmark")
                    }
                    .disabled(model.purchased.isEmpty)
                } label: {
                    Label("shopping.detail.more", systemImage: "ellipsis.circle")
                }
                .accessibilityIdentifier("shopping.detail.menu")
            }
        }
        .confirmationDialog(Text("shopping.detail.clearPurchased"), isPresented: $confirmClear) {
            Button("shopping.detail.clearPurchased", role: .destructive) { model.clearPurchased() }
            Button("common.cancel", role: .cancel) {}
        }
        .sheet(item: $editing) { target in
            if let item = model.item(for: target.id) {
                ShoppingItemFormView(item: item, services: services) { model.reload() }
            }
        }
        .sensoryFeedback(trigger: model.purchasedCount) { old, new in new > old ? .success : .selection }
        .shoppingErrorAlert(model.errorMessage) { model.dismissError() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: services.context)) { _ in model.reload() }
    }

    private var purchasedHeader: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { model.showPurchased.toggle() }
        } label: {
            HStack {
                Text("shopping.detail.purchased \(model.purchased.count)")
                Spacer()
                Image(systemName: "chevron.down")
                    .rotationEffect(model.showPurchased ? .zero : .degrees(-90))
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("shopping.detail.purchasedToggle")
        .accessibilityValue(Text(model.showPurchased ? LocalizedStringKey("shopping.detail.expanded")
                                                     : LocalizedStringKey("shopping.detail.collapsed")))
    }

    private func card(_ row: ShoppingListModel.Row) -> some View {
        HStack(spacing: 4) {
            ShoppingItemCheckbox(row: row) {
                withAnimation(reduceMotion ? nil : .snappy) { model.toggle(row.id) }
            }
            if let productID = row.productID {
                NavigationLink(value: ProductRoute(id: productID)) { ShoppingItemCardContent(row: row) }
                    .accessibilityHint(Text("shopping.item.openProductHint"))
                    .accessibilityIdentifier("shopping.item.\(row.name)")
            } else {
                Button { editing = EditTarget(id: row.id) } label: { ShoppingItemCardContent(row: row) }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("shopping.item.openFormHint"))
                    .accessibilityIdentifier("shopping.item.\(row.name)")
            }
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
        Button { editing = EditTarget(id: row.id) } label: {
            Label("common.edit", systemImage: "pencil")
        }
        .tint(.accentColor)
    }
}
