import HomassyCore
import SwiftUI

/// The bottom quick add bar: a field for a new item, product suggestions as you type, and a button for
/// the stepwise add sheet.
struct AddItemBar: View {
    @Bindable var model: ShoppingListModel
    /// Opens the stepwise add sheet with what has been typed so far.
    let openSteps: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            if !model.suggestions.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.suggestions) { suggestion in
                            Button { model.addSuggestion(suggestion.id) } label: { Text(verbatim: suggestion.name) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel(Text("shopping.addItem.suggestion \(suggestion.name)"))
                                .accessibilityIdentifier("shopping.suggestion.\(suggestion.name)")
                        }
                    }
                    .padding(.horizontal)
                }
            }
            HStack(spacing: 8) {
                Button(action: openSteps) {
                    Image(systemName: "list.number").font(.title3)
                }
                .accessibilityLabel(Text("shopping.addItem.steps"))
                .accessibilityIdentifier("shopping.addItem.steps")
                TextField("shopping.addItem.placeholder", text: $model.draftText)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .submitLabel(.done)
                    .onSubmit {
                        model.addDraft()
                        focused = true
                    }
                    .accessibilityIdentifier("shopping.addItem.field")
                Button { model.addDraft() } label: {
                    Image(systemName: "plus.circle.fill").font(.title2)
                }
                .disabled(!model.canAddDraft)
                .accessibilityLabel(Text("shopping.addItem.add"))
                .accessibilityIdentifier("shopping.addItem.submit")
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(.bar)
    }
}
