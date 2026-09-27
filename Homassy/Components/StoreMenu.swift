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

    private var chosen: Choice {
        if model.name == nil { return .none }
        return model.selectedStoreID.map(Choice.store) ?? .place
    }

    /// On while that row (a recent store, nil for "No store") is the chosen one. Any tap chooses it, the checked row
    /// too: that confirms the choice, so a later GPS suggestion no longer replaces it.
    private func isChosen(_ id: UUID?) -> Binding<Bool> {
        Binding {
            chosen == (id.map(Choice.store) ?? .none)
        } set: { _ in
            model.choose(id)
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
                // checkmark and is announced as selected. XCUITest cannot reach menu-item identifiers, so the UI
                // tests find these rows by their titles.
                Section {
                    ForEach(model.options) { option in
                        Toggle(isOn: isChosen(option.id)) {
                            Text(verbatim: option.name)
                            if let subtitle = directory.subtitle(ofStore: option.id) {
                                Text(verbatim: subtitle)
                            }
                        }
                        .accessibilityIdentifier("store.menu.\(option.name)")
                    }
                    Toggle(isOn: isChosen(nil)) { Text("store.none") }
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
