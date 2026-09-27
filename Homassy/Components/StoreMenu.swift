import HomassyCore
import SwiftUI

/// "Honnan" (P2-08a, store row option A): a pull-down menu, like Calendar's calendar row. It lists the GPS
/// suggestion with its distance, the recent stores and "No store" as an inline picker (so VoiceOver reads the chosen
/// one as selected), and "Other store…" (the full picker). The user picks; the GPS only suggests.
struct StoreMenu: View {
    let model: StoreMenuModel
    let other: () -> Void

    /// A row of the inline picker. An untouched Apple Maps suggestion is not a row: the menu's label names it.
    private enum Choice: Hashable {
        case none
        case store(UUID)
        case place
    }

    private var choice: Binding<Choice> {
        Binding {
            if model.name == nil { return .none }
            return model.selectedStoreID.map(Choice.store) ?? .place
        } set: { new in
            switch new {
            case .none: model.choose(nil)
            case .store(let id): model.choose(id)
            case .place: break
            }
        }
    }

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
                Picker(selection: choice) {
                    ForEach(model.options) { option in
                        Text(verbatim: option.name)
                            .tag(Choice.store(option.id))
                            .accessibilityIdentifier("store.menu.\(option.name)")
                    }
                    Text("store.none")
                        .tag(Choice.none)
                        .accessibilityIdentifier("store.menu.none")
                } label: {
                    Text("shopping.purchase.fromWhere")
                }
                .pickerStyle(.inline)
                Section {
                    Button(action: other) { Label("store.other", systemImage: "magnifyingglass") }
                        .accessibilityIdentifier("store.menu.other")
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
