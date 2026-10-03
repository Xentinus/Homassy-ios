import HomassyCore
import SwiftUI

/// Consume or move part of a stock item. The amount starts at the full remaining quantity and is capped at it;
/// the confirm button stays disabled outside (0, maximum]. Moving also needs a target from the searchable
/// list of the space's storage locations.
struct AmountSheet: View {
    typealias Purpose = ProductDetailView.AmountTarget.Purpose

    let purpose: Purpose
    @State private var form: AmountFormModel
    let targets: (String) -> [LocationOption]
    let onConfirm: (Decimal, UUID?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedTarget: LocationOption?

    init(purpose: Purpose, form: AmountFormModel, targets: @escaping (String) -> [LocationOption],
         onConfirm: @escaping (Decimal, UUID?) -> Void) {
        self.purpose = purpose
        _form = State(initialValue: form)
        self.targets = targets
        self.onConfirm = onConfirm
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Button { form.decrement() } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                            .disabled(!form.canDecrement)
                            .accessibilityLabel(Text("amount.decrease"))
                            .accessibilityIdentifier("amount.decrement")
                        TextField("amount.placeholder", text: $form.text)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .font(.title3.monospacedDigit())
                            .accessibilityIdentifier("amount.field")
                        Text(form.unit.shortLabel(for: form.value ?? 1)).foregroundStyle(.secondary)
                        Button { form.increment() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .disabled(!form.canIncrement)
                            .accessibilityLabel(Text("amount.increase"))
                            .accessibilityIdentifier("amount.increment")
                    }
                    .buttonStyle(.borderless)
                } header: {
                    Text("amount.title")
                } footer: {
                    Text("amount.maximum \(form.maximumText)")
                        .foregroundStyle(form.isValid || form.text.isEmpty ? Color.secondary : Palette.expiryCritical)
                }
                if purpose == .move {
                    Section("amount.moveTo") {
                        ForEach(targets(query)) { option in
                            Button { selectedTarget = option } label: {
                                HStack {
                                    Label { option.name.map { Text($0) } ?? Text("product.detail.noLocation") } icon: {
                                        Image(systemName: option.id == nil ? "tray" : "archivebox")
                                    }
                                    Spacer()
                                    if selectedTarget == option {
                                        Image(systemName: "checkmark").foregroundStyle(Palette.accent)
                                    }
                                }
                            }
                            .foregroundStyle(.primary)
                            .accessibilityAddTraits(selectedTarget == option ? .isSelected : [])
                            .accessibilityIdentifier("move.target.\(option.name ?? "none")")
                        }
                    }
                }
            }
            .navigationTitle(purpose == .consume ? "amount.consume.title" : "amount.move.title")
            .navigationBarTitleDisplayMode(.inline)
            .modifier(MoveTargetSearch(isEnabled: purpose == .move, query: $query))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { SheetCancelButton { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(purpose == .consume ? "product.detail.consume" : "product.detail.move") {
                        guard let amount = form.value else { return }
                        onConfirm(amount, selectedTarget?.id)
                        dismiss()
                    }
                    .disabled(!canConfirm)
                    .accessibilityIdentifier("amount.confirm")
                }
            }
        }
        .presentationDetents(purpose == .consume ? [.medium, .large] : [.large])
    }

    private var canConfirm: Bool {
        form.isValid && (purpose == .consume || selectedTarget != nil)
    }
}

/// The location search, only for the move sheet (a space can have many storage locations).
private struct MoveTargetSearch: ViewModifier {
    let isEnabled: Bool
    @Binding var query: String

    func body(content: Content) -> some View {
        if isEnabled {
            content.searchable(text: $query, prompt: Text("amount.moveTo.search"))
        } else {
            content
        }
    }
}
