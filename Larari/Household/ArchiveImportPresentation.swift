import LarariCore
import SwiftUI

/// Presents the import sheet for this window's pending archive, or the failure alert (P3-04). N-03 moved it out of
/// `MainTabView`, so a list or product window presents an archive opened into it as well. Before importing it
/// saves every window's pending changes, not just this window's.
private struct ArchiveImportPresentation: ViewModifier {
    @Environment(AppModel.self) private var app
    @Environment(ServiceContainer.self) private var services
    @Environment(ArchiveImportRouter.self) private var archiveRouter
    @Environment(SpaceSelection.self) private var selection

    func body(content: Content) -> some View {
        content
            .sheet(item: Bindable(archiveRouter).pending) { pending in
                if let archive = services.archive {
                    ImportFlowView(url: pending.url, archive: archive,
                                   commitPendingChanges: { [app] in try app.undoQueues.commitAll() }) { space in
                        selection.select(space)
                    }
                }
            }
            .alert(Text("archive.import.failed.title"),
                   isPresented: Binding(get: { archiveRouter.errorMessage != nil },
                                        set: { if !$0 { archiveRouter.errorMessage = nil } })) {
                Button("archive.ok", role: .cancel) {}
            } message: {
                Text(verbatim: archiveRouter.errorMessage ?? "")
            }
    }
}

extension View {
    func archiveImportPresentation() -> some View {
        modifier(ArchiveImportPresentation())
    }
}
