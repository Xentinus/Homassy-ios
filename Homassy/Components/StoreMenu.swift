import HomassyCore
import SwiftUI

/// "Honnan" (P2-08a, store row option A): a pull-down menu, like Calendar's calendar row. It lists the GPS
/// suggestion with its distance, the recent stores with a checkmark on the chosen one, "Other store…" (the full
/// picker) and "No store". The user picks; the GPS only suggests.
struct StoreMenu: View {
    let model: StoreMenuModel
    let other: () -> Void

    var body: some View {
        LabeledContent("shopping.purchase.fromWhere") {
            Menu {
                if model.offersSuggestion, let suggestion = model.suggestion {
                    Section {
                        Button {
                            model.chooseSuggestion()
                        } label: {
                            Label {
                                Text(verbatim: suggestion.name)
                                Text("store.suggested \(StoreSuggestionRow.format(suggestion.distance))")
                            } icon: {
                                Image(systemName: "location.fill")
                            }
                        }
                        .accessibilityIdentifier("store.menu.suggestion")
                    }
                }
                if !model.options.isEmpty {
                    Section {
                        ForEach(model.options) { option in
                            Button {
                                model.choose(option.id)
                            } label: {
                                if option.id == model.selectedStoreID {
                                    Label(option.name, systemImage: "checkmark")
                                } else {
                                    Text(verbatim: option.name)
                                }
                            }
                            .accessibilityIdentifier("store.menu.\(option.name)")
                        }
                    }
                }
                Section {
                    Button(action: other) { Label("store.other", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("store.menu.other")
                    Button {
                        model.choose(nil)
                    } label: {
                        if model.name == nil {
                            Label("store.none", systemImage: "checkmark")
                        } else {
                            Text("store.none")
                        }
                    }
                    .accessibilityIdentifier("store.menu.none")
                }
            } label: {
                HStack(spacing: 4) {
                    if model.suggestedDistance != nil {
                        Image(systemName: "location.fill").imageScale(.small).accessibilityHidden(true)
                    }
                    if let name = model.name {
                        if let distance = model.suggestedDistance {
                            Text(verbatim: "\(name) · \(StoreSuggestionRow.format(distance))")
                        } else {
                            Text(verbatim: name)
                        }
                    } else {
                        Text("store.none")
                    }
                }
                // The whole row after "From where" opens the menu, like Calendar's calendar row.
                .frame(maxWidth: .infinity, alignment: .trailing)
                .contentShape(Rectangle())
            }
            .accessibilityIdentifier("store.menu")
        }
    }
}
