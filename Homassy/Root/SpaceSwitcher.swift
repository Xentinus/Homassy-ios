import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Toolbar menu listing Personal and every household, with a checkmark on the selected one.
struct SpaceSwitcher: View {
    @Environment(AppModel.self) private var app
    @Environment(SpaceSelection.self) private var selection
    @Environment(ServiceContainer.self) private var services
    @State private var spaces: [Space] = []
    @State private var isCreatingHousehold = false

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
            Button("space.new", systemImage: "plus") { isCreatingHousehold = true }
                .disabled(services.sharing == nil)
                .accessibilityIdentifier("space.new")
        } label: {
            Label(current?.name ?? "", systemImage: current?.kind == .household ? "house.fill" : "person.crop.circle")
                .labelStyle(.titleAndIcon)
        }
        .accessibilityIdentifier("spaceSwitcher")
        .sheet(isPresented: $isCreatingHousehold) {
            if let sharing = services.sharing { NewHouseholdSheet(service: sharing) }
        }
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
