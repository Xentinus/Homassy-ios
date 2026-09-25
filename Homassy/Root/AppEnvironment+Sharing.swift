import HomassyCore
import SwiftUI

/// Asks the root to run the P3-04 export for a space (the leave and delete flows offer it first).
struct ExportRequestAction {
    let handler: @MainActor (Space) -> Void
    @MainActor func callAsFunction(_ space: Space) { handler(space) }
}

extension EnvironmentValues {
    @Entry var requestExport = ExportRequestAction { _ in }
}
