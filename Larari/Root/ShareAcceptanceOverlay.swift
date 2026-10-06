import LarariCore
import SwiftUI

/// While an invitation is being accepted, a capsule at the top; on failure, an alert with Try again. With several
/// iPad windows only the owning window shows either (N-03).
struct ShareAcceptanceOverlay: ViewModifier {
    @Bindable var model: ShareAcceptanceModel
    let isOwner: Bool

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                if isOwner && model.isBusy {
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
            get: {
                guard isOwner else { return false }
                if case .failed = model.state { return true } else { return false }
            },
            set: { _ in }
        )
    }
}

extension View {
    func shareAcceptanceOverlay(_ model: ShareAcceptanceModel, isOwner: Bool = true) -> some View {
        modifier(ShareAcceptanceOverlay(model: model, isOwner: isOwner))
    }
}
