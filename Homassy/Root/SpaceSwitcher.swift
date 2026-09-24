import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Toolbar menu listing Personal and every household, with a checkmark on the selected one.
struct SpaceSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(SpaceSelection.self) private var selection
    @State private var spaces: [Space] = []

    var body: some View {
        let current = selection.resolve(in: spaces)
        Menu {
            ForEach(spaces, id: \.objectID) { space in
                Button {
                    selection.select(space)
                } label: {
                    if space.objectID == current?.objectID {
                        Label(space.name, systemImage: "checkmark")
                    } else {
                        Text(space.name)
                    }
                }
            }
            Divider()
            // Enabled by P5-01, which adds household creation and sharing.
            Button("space.new", systemImage: "plus") {}
                .disabled(true)
        } label: {
            Label(current?.name ?? "", systemImage: current?.kind == .household ? "house.fill" : "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("spaceSwitcher")
        .accessibilityHint(Text("space.switcher"))
        .task { reload() }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextObjectsDidChange,
                                                        object: app.persistence.viewContext)) { _ in
            reload()
        }
    }

    private func reload() {
        spaces = (try? app.spaceStore.allSpaces()) ?? []
    }
}
