import HomassyCore
import SwiftUI

/// "Honnan" (P2-08a, store row option A): a pull-down menu, like Calendar's calendar row. It lists the GPS
/// suggestion with its distance, the recent stores with their address and "No store" as checkmark toggles (so
/// VoiceOver reads the chosen one as selected), and "Other store…" (the full picker). The user picks; the GPS only
/// suggests.
struct StoreMenu: View {
    let model: StoreMenuModel
    let other: () -> Void

    @Environment(StoreDirectory.self) private var directory

    /// A checkmark row. An untouched Apple Maps suggestion is not a row: the menu's label names it.
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

    /// On while `row` is the chosen one; turning it on chooses it. Turning the chosen row off does nothing.
    private func isChosen(_ row: Choice) -> Binding<Bool> {
        Binding {
            choice.wrappedValue == row
        } set: { isOn in
            if isOn { choice.wrappedValue = row }
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
                // Toggles, not an inline Picker: a menu keeps only the first Text of a Picker row, so the address
                // would be dropped. A menu Toggle keeps the second Text as the row's subtitle, shows the system
                // checkmark and is announced as selected.
                Section {
                    ForEach(model.options) { option in
                        Toggle(isOn: isChosen(.store(option.id))) {
                            Text(verbatim: option.name)
                            if let subtitle = directory.subtitle(ofStore: option.id) {
                                Text(verbatim: subtitle)
                            }
                        }
                        .accessibilityIdentifier("store.menu.\(option.name)")
                    }
                    Toggle(isOn: isChosen(.none)) { Text("store.none") }
                        .accessibilityIdentifier("store.menu.none")
                }
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
                            Text(verbatim: directory.compactName(ofStore: model.selectedStoreID) ?? name)
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
        .task { await directory.refreshLocation() }
    }
}
