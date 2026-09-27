import CoreData
import HomassyCore
import SwiftUI

/// The stepwise add: 1. what (a product or a new custom item), 2. how much, 3. where from.
struct AddItemSheet: View {
    let services: ServiceContainer

    @State private var model: AddItemFlowModel
    @State private var authorizer = CoreLocationAuthorizer()
    @State private var pickingStore: StorePickerModel.Tab?
    @State private var recent: [ShoppingLocation] = []
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(StoreDirectory.self) private var directory

    init(list: ShoppingList, services: ServiceContainer, initialQuery: String = "") {
        self.services = services
        let model = AddItemFlowModel(list: list, shopping: services.shopping, locations: services.shoppingLocations)
        model.query = initialQuery
        _model = State(initialValue: model)
    }

    var body: some View {
        NavigationStack {
            Form {
                switch model.step {
                case .what: whatPage
                case .amount: amountPage
                case .store: storePage
                }
                if let error = model.errorMessage {
                    Section { Text(verbatim: error).foregroundStyle(.red) }
                }
            }
            .navigationTitle(Text("shopping.add.title \(model.stepNumber) \(AddItemFlowModel.Step.allCases.count)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .sheet(item: $pickingStore) { tab in
                if let space = model.space {
                    StorePickerView(space: space, services: services, initialTab: tab) { model.setStore($0) }
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
            if model.step == .what {
                Button("common.cancel") { dismiss() }
            } else {
                Button("shopping.add.back") { model.back() }
                    .accessibilityIdentifier("shopping.add.back")
            }
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.step == .store {
                Button("shopping.add.confirm") { if model.add() { dismiss() } }
                    .accessibilityIdentifier("shopping.add.confirm")
            } else {
                Button("shopping.add.next") { model.next() }
                    .disabled(!model.canAdvance)
                    .accessibilityIdentifier("shopping.add.next")
            }
        }
    }

    @ViewBuilder private var whatPage: some View {
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
            StoreSuggestionRow(name: model.storeName, distance: model.suggestedDistance) { pickingStore = .recent }
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
            Button { pickingStore = .nearby } label: { Label("shopping.add.map", systemImage: "map") }
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
