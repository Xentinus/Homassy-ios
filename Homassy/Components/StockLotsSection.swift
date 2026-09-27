import HomassyCore
import SwiftUI

/// The lots of an addition (P2-08a, layout 2A): per lot, the amount with a stepper, then the storage menu and the
/// expiry button; a green "Add batch" row and a red minus per lot, like Contacts. Shared by the add-stock sheet
/// and the purchase sheet.
struct StockLotsSection: View {
    @Bindable var lots: StockLotsModel
    let unit: MeasureUnit
    /// Expiry cannot be before this day.
    let purchasedAt: Date
    /// The purchase sheet's listed amount: the footer then reads "Total 2 of 3 pcs".
    var listedText: String?
    var header: LocalizedStringKey = "stock.lots"

    @FocusState private var focusedLot: UUID?

    var body: some View {
        Section {
            ForEach($lots.lots) { $lot in
                let number = (lots.lots.firstIndex { $0.id == lot.id } ?? 0) + 1
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        if lots.canRemove {
                            Button {
                                withAnimation { lots.remove(lot.id) }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.white, .red)
                                    .imageScale(.large)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(Text("stock.lot.remove \(number)"))
                            .accessibilityIdentifier("lot.\(number).remove")
                        }
                        // The field hugs the amount so the unit sits right after it; the whole amount-and-unit
                        // area (at least 88 pt wide, the stepper's height) focuses the field.
                        HStack(spacing: 4) {
                            TextField("stock.quantity", text: $lot.quantityText, prompt: Text(verbatim: "0"))
                                .keyboardType(.decimalPad)
                                .fixedSize()
                                .focused($focusedLot, equals: lot.id)
                                .accessibilityIdentifier("lot.\(number).quantity")
                            Text(verbatim: unit.shortLabel(for: lots.quantity(of: lot.id) ?? 1))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minWidth: 88, maxHeight: .infinity, alignment: .leading)
                        .contentShape(Rectangle())
                        .onTapGesture { focusedLot = lot.id }
                        Spacer(minLength: 0)
                        Stepper("stock.quantity", onIncrement: { lots.step(lot.id, by: 1) },
                                onDecrement: { lots.step(lot.id, by: -1) })
                            .labelsHidden()
                            .fixedSize()
                            .accessibilityIdentifier("lot.\(number).stepper")
                    }
                    Group {
                        LabeledContent("stock.location") {
                            Picker(selection: $lot.storageLocationID) {
                                Text("inventory.noLocation").tag(UUID?.none)
                                ForEach(lots.storageOptions) { Text(verbatim: $0.name).tag(Optional($0.id)) }
                            } label: {
                                Text("stock.location")
                            }
                            .pickerStyle(.menu)
                            .labelsHidden()
                            .accessibilityIdentifier("lot.\(number).location")
                        }
                        LabeledContent("stock.expiresAt") {
                            ExpiryButton(date: $lot.expiresAt, minimum: purchasedAt)
                                .accessibilityIdentifier("lot.\(number).expiry")
                        }
                    }
                    .padding(.leading, lots.canRemove ? 34 : 0)
                    if let error = lots.quantityErrors[lot.id] {
                        Text(verbatim: error).font(.footnote).foregroundStyle(.red)
                    }
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel(Text("stock.lot.label \(number)"))
            }
            if lots.allowsMultiple {
                Button {
                    withAnimation { lots.addLot() }
                } label: {
                    Label {
                        Text("stock.lot.add")
                    } icon: {
                        Image(systemName: "plus.circle.fill")
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .green)
                            .imageScale(.large)
                    }
                }
                .accessibilityIdentifier("lot.add")
            }
        } header: {
            Text(header)
        } footer: {
            footer
        }
    }

    @ViewBuilder private var footer: some View {
        if let total = lots.total {
            let totalText = Quantity.format(total, unit: unit, locale: .current)
            if let listedText {
                Text("stock.lot.totalOf \(totalText) \(listedText)")
            } else {
                HStack(spacing: 0) {
                    Text("stock.lot.total \(totalText)")
                    Text(verbatim: " · ")
                    Text("stock.lot.count \(lots.lotCount)")
                }
            }
        }
    }
}

/// A lot's expiry: the short date, or "none". A tap opens a calendar popover with "No expiry date". The day
/// shown when the popover closes becomes the expiry, even the preselected one, unless "No expiry date" was tapped.
private struct ExpiryButton: View {
    @Binding var date: Date?
    let minimum: Date

    @State private var showing = false
    @State private var draft = Date.now
    @State private var cleared = false

    var body: some View {
        Button {
            draft = date ?? Calendar.current.date(byAdding: .day, value: 7, to: minimum) ?? minimum
            cleared = false
            showing = true
        } label: {
            if let date {
                Text(date, format: .dateTime.month(.abbreviated).day())
            } else {
                Text("stock.expiry.none")
            }
        }
        .buttonStyle(.bordered)
        .accessibilityValue(date.map { Text($0, format: .dateTime.month(.wide).day()) } ?? Text("stock.expiry.none"))
        .onChange(of: showing) { _, open in
            if !open, !cleared { date = draft }
        }
        .popover(isPresented: $showing) {
            VStack(spacing: 12) {
                DatePicker("stock.expiresAt", selection: $draft, in: Calendar.current.startOfDay(for: minimum)...,
                           displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .onChange(of: draft) { _, new in date = new }
                Button("stock.noExpiry") {
                    cleared = true
                    date = nil
                    showing = false
                }
                .accessibilityIdentifier("lot.noExpiry")
            }
            .padding()
            .frame(minWidth: 320)
            .presentationCompactAdaptation(.popover)
        }
    }
}
