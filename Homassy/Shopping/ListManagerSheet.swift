import HomassyCore
import SwiftUI

/// "Listák kezelése" (P4-03a): the space's lists in edit mode. Drag reorders (the filter strip follows), delete asks
/// first, a tap opens the name and colour editor, and "New list" sits under the lists. The "N to buy" line doubles as
/// the attribution caption for a list another member just changed (P5-04).
struct ListManagerSheet: View {
    let model: ShoppingListsModel
    @State private var editor: ListEditorSheet.Mode?
    @State private var pendingDelete: ShoppingListsModel.Summary?
    @State private var editMode: EditMode = .active
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.summaries) { summary in
                        Button { editor = .edit(summary.id) } label: { row(summary) }
                            .navigationRowStyle()
                            .accessibilityIdentifier("shopping.manage.row.\(summary.name)")
                    }
                    .onMove { model.move(fromOffsets: $0, toOffset: $1) }
                    .onDelete { offsets in pendingDelete = offsets.first.map { model.summaries[$0] } }
                } footer: {
                    Text("shopping.manage.footer")
                }
                Section {
                    Button { editor = .create } label: { Label("shopping.lists.new", systemImage: "plus") }
                        .accessibilityIdentifier("shopping.manage.new")
                }
            }
            .environment(\.editMode, $editMode)
            .navigationTitle(Text("shopping.manage"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.done") { dismiss() }
                        .accessibilityIdentifier("shopping.manage.done")
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
            .onAppear { model.reload() }
        }
    }

    private func row(_ summary: ShoppingListsModel.Summary) -> some View {
        HStack(spacing: 12) {
            Circle().fill(ListColor.color(summary.color)).frame(width: 12, height: 12).accessibilityHidden(true)
            Text(verbatim: summary.name).foregroundStyle(.primary)
            Spacer(minLength: 8)
            AttributionCaption(ids: [summary.id]) {
                Text("shopping.lists.remaining \(summary.remaining)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: "chevron.forward")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
    }
}
