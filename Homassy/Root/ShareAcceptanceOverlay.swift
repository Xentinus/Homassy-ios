import HomassyCore
import SwiftUI

/// While an invitation is being accepted, a capsule at the top; on failure, an alert with Try again.
struct ShareAcceptanceOverlay: ViewModifier {
    @Bindable var model: ShareAcceptanceModel

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if model.isBusy {
                    HStack(spacing: 12) {
                        ProgressView()
                        Text("share.accept.joining")
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 8)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("share.accept.joining")
                }
            }
            .alert(Text("share.accept.failed.title"), isPresented: isFailed) {
                Button("share.accept.retry") { Task { await model.retry() } }
                Button("common.cancel", role: .cancel) { model.reset() }
            } message: {
                if case let .failed(failure) = model.state { Text(verbatim: failure.errorDescription ?? "") }
            }
    }

    private var isFailed: Binding<Bool> {
        Binding(
            get: { if case .failed = model.state { true } else { false } },
            set: { _ in }
        )
    }
}

extension View {
    func shareAcceptanceOverlay(_ model: ShareAcceptanceModel) -> some View {
        modifier(ShareAcceptanceOverlay(model: model))
    }
}
