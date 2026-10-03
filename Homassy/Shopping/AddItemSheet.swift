import CoreData
import HomassyCore
import SwiftUI

/// The stepwise add: 0. which list (with two or more), 1. what (a product or a new custom item), 2. how much,
/// 3. where from. It can also open on 2. how much with a product chosen in the product detail.
struct AddItemSheet: View {
    let services: ServiceContainer
    private let startsWithProduct: Bool

    @State private var model: AddItemFlowModel
    @State private var authorizer = CoreLocationAuthorizer()
    @State private var pickingStore = false
    @State private var recent: [ShoppingLocation] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreDirectory.self) private var directory

    init(lists: [ShoppingList], preselected: UUID?, services: ServiceContainer, initialQuery: String = "",
         product: Product? = nil) {
        self.services = services
        let model = AddItemFlowModel(lists: lists, preselected: preselected,
                                     lastUsed: LastUsedShoppingList(defaults: TabDefaults.store),
                                     shopping: services.shopping, locations: services.shoppingLocations)
        model.query = initialQuery
        if let product { model.start(with: product) }
        startsWithProduct = product != nil
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.step {
                case .what: whatPage
                case .amount: amountPage
                case .store: storePage.task { await directory.refreshLocation() }
                }
                if let error = model.errorMessage {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("shopping.add.title \(model.stepNumber) \(AddItemFlowModel.Step.allCases.count)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(isPresented: $pickingStore) {
                if let space = model.space {
                    StorePickerView(space: space, services: services) { model.setStore($0) }
                }
            }
            .task(id: model.step) {
                guard model.step == .store, let space = model.space else { return }
                recent = (try? services.shoppingLocations.recent(in: space, limit: 5)) ?? []
                if let suggestion = await StoreSuggestionLoader.suggestion(for: space, services: services,
                                                                             authorizer: authorizer) {
                    model.applySuggestion(suggestion)
                }
            }
        }
        .presentationDetents([.large])
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            // With a product chosen up front, "how much" is the first page, so it offers Cancel rather than a Back to nowhere.
            if model.step == .what || (startsWithProduct && model.step == .amount) {
                SheetCancelButton { dismiss() }
            } else {
                Button("shopping.add.back") { model.back() }
                    .accessibilityIdentifier("shopping.add.back")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.step == .store {
                SheetConfirmButton(title: "shopping.add.confirm") { if model.add() { dismiss() } }
                    .accessibilityIdentifier("shopping.add.confirm")
            } else {
                Button("shopping.add.next") { model.next() }
                    .disabled(!model.canAdvance)
                    .accessibilityIdentifier("shopping.add.next")
            }
        }
    }

    /// Menu items draw template images, so the colour is baked in to survive.
    @ViewBuilder private func listDot(_ color: String?) -> some View {
        if let dot = UIImage(systemName: "circle.fill")?
            .withTintColor(UIColor(ListColor.color(color)), renderingMode: .alwaysOriginal) {
            Image(uiImage: dot)
        } else {
            Image(systemName: "circle.fill")
        }
    }

    /// The "Lista" row: on the first page, or on "how much" when the sheet started with a product (P2-07a).
    @ViewBuilder private var listPicker: some View {
        if model.listOptions.count > 1 {
            Section {
                Picker("shopping.add.list", selection: $model.selectedListID) {
                    ForEach(model.listOptions) { option in
                        Label {
                            Text(verbatim: option.name)
                        } icon: {
                            listDot(option.color)
                        }
                        .tag(Optional(option.id))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("shopping.add.list")
            }
        }
    }

    @ViewBuilder private var whatPage: some View {
        listPicker
        Section {
            TextField("shopping.add.query", text: $model.query)
                .focused($focused)
                .submitLabel(.next)
                .onSubmit { if model.canAdvance { model.next() } }
                .accessibilityIdentifier("shopping.add.query")
        } header: {
            Text("shopping.add.what")
        }
        if !model.suggestions.isEmpty {
            Section {
                ForEach(model.suggestions) { suggestion in
                    Button { model.chooseProduct(suggestion.id) } label: {
                        Label { Text(verbatim: suggestion.name) } icon: { Image(systemName: "shippingbox") }
                    }
                    .accessibilityIdentifier("shopping.add.suggestion.\(suggestion.name)")
                }
            } header: {
                Text("shopping.add.products")
            }
        }
        if let text = model.query.nilIfBlankForView {
            Section {
                Button { model.chooseCustom() } label: {
                    Label { Text("shopping.add.custom \(text)") } icon: { Image(systemName: "plus") }
                }
                .accessibilityIdentifier("shopping.add.custom")
            }
        }
    }

    @ViewBuilder private var amountPage: some View {
        if startsWithProduct { listPicker }
        Section {
            if let name = model.chosenName {
                Text(verbatim: name).font(.headline)
            }
            HStack {
                TextField("shopping.form.quantity", text: $model.quantityText)
                    .keyboardType(.decimalPad)
                    .accessibilityIdentifier("shopping.add.quantity")
                Picker("shopping.form.unit", selection: $model.unit) {
                    ForEach(model.units, id: \.self) { Text(verbatim: model.unitLabel($0)).tag($0) }
                }
                .labelsHidden()
            }
        } header: {
            Text("shopping.add.howMuch")
        }
    }

    @ViewBuilder private var storePage: some View {
        Section {
            StoreSuggestionRow(name: model.storeName, distance: model.suggestedDistance) { pickingStore = true }
        } header: {
            Text("shopping.add.where")
        }
        if !recent.isEmpty {
            Section {
                ForEach(recent, id: \.objectID) { store in
                    Button { model.setStore(store) } label: {
                        Label {
                            Text(verbatim: directory.compactName(ofStore: store.publicId) ?? store.name)
                            if let subtitle = directory.subtitle(ofStore: store.publicId) {
                                Text(verbatim: subtitle).font(.caption).foregroundStyle(.secondary)
                            }
                        } icon: { Image(systemName: "clock") }
                    }
                }
            } header: {
                Text("store.tab.recent")
            }
        }
        Section {
            Button { pickingStore = true } label: { Label("shopping.add.map", systemImage: "map") }
                .accessibilityIdentifier("shopping.add.map")
            Button { model.setStore(nil) } label: { Label("shopping.form.store.none", systemImage: "cart") }
                .accessibilityIdentifier("shopping.add.anyStore")
        }
    }
}

private extension String {
    var nilIfBlankForView: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
