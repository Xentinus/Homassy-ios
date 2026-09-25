import CoreData
import HomassyCore
import SwiftUI

/// The lists overview. A card per list; swipe edits or deletes, drag reorders. With compact height
/// (iPhone landscape) it becomes a two-column grid with context menus.
struct ShoppingListsView: View {
    let services: ServiceContainer

    @State private var model: ShoppingListsModel
    @State private var editor: ListEditorSheet.Mode?
    @State private var pendingDelete: ShoppingListsModel.Summary?
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(space: Space, services: ServiceContainer) {
        self.services = services
        _model = State(initialValue: ShoppingListsModel(service: services.shopping, space: space))
    }

    var body: some View {
        content
            .navigationTitle(Text("shopping.lists.title"))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { SpaceSwitcher() }
                ToolbarItem(placement: .primaryAction) {
                    AddMenu {
                        Button { editor = .create } label: { Label("add.shoppingList", systemImage: "list.bullet") }
                            .accessibilityIdentifier("addMenu.shoppingItem")
                    }
                }
            }
            .sheet(item: $editor) { mode in ListEditorSheet(mode: mode, model: model) }
            .confirmationDialog(Text("shopping.lists.delete.confirm \(pendingDelete?.name ?? "")"),
                                isPresented: Binding(get: { pendingDelete != nil },
                                                     set: { if !$0 { pendingDelete = nil } }),
                                titleVisibility: .visible) {
                Button("shopping.lists.delete.action", role: .destructive) {
                    if let summary = pendingDelete { model.delete(summary.id) }
                    pendingDelete = nil
                }
                Button("common.cancel", role: .cancel) { pendingDelete = nil }
            }
            .shoppingErrorAlert(model.errorMessage) { model.dismissError() }
            .onAppear { model.reload() }
            .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                            object: services.context)) { _ in model.reload() }
    }

    @ViewBuilder private var content: some View {
        if model.summaries.isEmpty {
            ContentUnavailableView {
                Label("shopping.lists.empty.title", systemImage: "cart")
            } description: {
                Text("shopping.lists.empty.message")
            } actions: {
                Button("shopping.lists.new") { editor = .create }
                    .buttonStyle(.borderedProminent)
            }
        } else if verticalSizeClass == .compact {
            ScrollView {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                          spacing: 12) {
                    ForEach(model.summaries) { summary in
                        NavigationLink(value: ShoppingListRoute(id: summary.id)) {
                            ShoppingListCard(summary: summary)
                                .padding()
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color(uiColor: .secondarySystemGroupedBackground),
                                            in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .attributionRing([summary.id], cornerRadius: 14)
                        }
                        .buttonStyle(.plain)
                        .contextMenu { actions(for: summary) }
                        .accessibilityIdentifier("shopping.list.\(summary.name)")
                    }
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
        } else {
            List {
                ForEach(model.summaries) { summary in
                    NavigationLink(value: ShoppingListRoute(id: summary.id)) { ShoppingListCard(summary: summary) }
                        .accessibilityIdentifier("shopping.list.\(summary.name)")
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { pendingDelete = summary } label: {
                                Label("common.delete", systemImage: "trash")
                            }
                            Button { editor = .edit(summary.id) } label: {
                                Label("common.edit", systemImage: "pencil")
                            }
                        }
                        .contextMenu { actions(for: summary) }
                }
                .onMove { model.move(fromOffsets: $0, toOffset: $1) }
            }
            .listRowSpacing(8)
        }
    }

    @ViewBuilder private func actions(for summary: ShoppingListsModel.Summary) -> some View {
        Button { editor = .edit(summary.id) } label: { Label("common.edit", systemImage: "pencil") }
        Button(role: .destructive) { pendingDelete = summary } label: {
            Label("common.delete", systemImage: "trash")
        }
    }
}
