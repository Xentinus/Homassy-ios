import SwiftUI

extension View {
    func shoppingErrorAlert(_ message: String?, dismiss: @escaping () -> Void) -> some View {
        alert(Text("common.error"),
              isPresented: Binding(get: { message != nil }, set: { if !$0 { dismiss() } })) {
            Button("common.ok", role: .cancel) { dismiss() }
        } message: {
            Text(verbatim: message ?? "")
        }
    }
}
