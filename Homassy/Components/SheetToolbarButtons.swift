import SwiftUI

/// iOS 26 sheet toolbar buttons (P2-07b, 5A): a glass ✕ to cancel or close, a tinted ✓ to save, add or finish, as in
/// Contacts and Calendar. The label keeps its words, so VoiceOver, Voice Control and the UI tests still find "Cancel".
struct SheetCancelButton: View {
    var title: LocalizedStringKey = "common.cancel"
    /// `.close` for sheets that only show something (Bezárás); `.cancel` where closing drops an edit.
    var role: ButtonRole = .cancel
    let action: () -> Void

    var body: some View {
        Button(role: role, action: action) { Label(title, systemImage: "xmark") }
            .labelStyle(.iconOnly)
    }
}

struct SheetConfirmButton: View {
    var title: LocalizedStringKey = "common.save"
    let action: () -> Void

    var body: some View {
        Button(role: .confirm, action: action) { Label(title, systemImage: "checkmark") }
            .labelStyle(.iconOnly)
    }
}
