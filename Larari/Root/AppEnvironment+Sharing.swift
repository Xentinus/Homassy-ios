import LarariCore
import SwiftUI

/// Asks the root to run the P3-04 export for a space (the leave and delete flows offer it first).
struct ExportRequestAction {
    let handler: @MainActor (Space) -> Void
    @MainActor func callAsFunction(_ space: Space) { handler(space) }
}

/// Name and colour of a member of the selected space, by userRecordName (attribution, P5-04).
struct MemberLookup {
    let name: @MainActor (String) -> String
    let colorKey: @MainActor (String) -> String?

    static let none = MemberLookup(name: { _ in "" }, colorKey: { _ in nil })
}

extension EnvironmentValues {
    @Entry var requestExport = ExportRequestAction { _ in }
    @Entry var memberLookup = MemberLookup.none
}
