import Foundation

/// Localised toast titles, matching the web app's `undo.item.*` and `undo.collapsed.*` strings.
public enum UndoTitle {
    public static func removed(_ name: String) -> String {
        String(localized: "undo.item.delete \(name)", bundle: .module, comment: "Undo toast: one item deleted")
    }

    public static func purchased(_ name: String) -> String {
        String(localized: "undo.item.purchase \(name)", bundle: .module, comment: "Undo toast: one item marked purchased")
    }

    public static func moved(_ name: String) -> String {
        String(localized: "undo.item.move \(name)", bundle: .module, comment: "Undo toast: one item moved")
    }

    public static func consumed(_ name: String) -> String {
        String(localized: "undo.item.consume \(name)", bundle: .module, comment: "Undo toast: one item used up")
    }

    public static func usedUp(_ name: String) -> String {
        String(localized: "undo.item.usedUp \(name)", bundle: .module, comment: "Undo toast: one item used up completely")
    }

    /// Several pending actions. `kind` is nil when they are of different kinds; `.generic` reads the same as mixed.
    public static func collapsed(kind: UndoKind?, count: Int) -> String {
        switch kind {
        case .delete: String(localized: "undo.collapsed.delete \(count)", bundle: .module, comment: "Undo toast: items deleted")
        case .purchase: String(localized: "undo.collapsed.purchase \(count)", bundle: .module, comment: "Undo toast: items purchased")
        case .move: String(localized: "undo.collapsed.move \(count)", bundle: .module, comment: "Undo toast: items moved")
        case .consume: String(localized: "undo.collapsed.consume \(count)", bundle: .module, comment: "Undo toast: items used up")
        case .generic, nil: String(localized: "undo.collapsed.mixed \(count)", bundle: .module, comment: "Undo toast: mixed changes")
        }
    }
}
