import SwiftUI
import UIKit

extension View {
    /// A row that opens or picks something (a list, a store), not one that runs an action: the label is drawn in the
    /// label colour instead of the tint, so `.primary` and `.secondary` inside it mean what they say (X-04 2A, as in
    /// Settings and Maps results). Action rows ("New list", "Add batch") keep the tint.
    func navigationRowStyle() -> some View {
        tint(Color(uiColor: .label))
    }
}
