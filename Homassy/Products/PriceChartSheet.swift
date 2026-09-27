import Charts
import HomassyCore
import SwiftUI

/// "Auchan · Budaörs" for a known store, the raw store name from the purchase otherwise, or the placeholder
/// when neither is known.
private func storeTitle(for line: PriceSummary.StoreLine, directory: StoreDirectory) -> Text {
    (line.storeID.flatMap { directory.compactName(ofStore: $0) } ?? line.name)
        .map { Text(verbatim: $0) } ?? Text("product.detail.unknownStore")
}

/// One store on the price trend card: its name, the latest unit price and when it was bought.
struct PriceStoreRow: View {
    let model: ProductDetailModel
    let line: PriceSummary.StoreLine

    @Environment(StoreDirectory.self) private var directory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                storeTitle(for: line, directory: directory)
                Text(line.latest.date, format: .dateTime.year().month().day())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(verbatim: model.unitPriceText(line.latest))
                .font(.body.weight(.semibold))
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("price.store.hint"))
    }
}

/// A store's unit price over time (user request, 2026-09-25), with its purchases below.
struct PriceChartSheet: View {
    let model: ProductDetailModel
    let line: PriceSummary.StoreLine

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(StoreDirectory.self) private var directory

    private var entries: [PriceEntry] { model.chartEntries(storeKey: line.key) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    chart
                        .frame(height: 220)
                        .padding(.vertical, 8)
                        .accessibilityIdentifier("price.chart")
                } footer: {
                    Text("price.chart.footer \(model.unitPriceText(line.latest)) \(entries.count)")
                }
                Section("price.history") {
                    ForEach(entries.reversed()) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.date, format: .dateTime.year().month().day())
                                Text(verbatim: model.quantityText(entry)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                Text(verbatim: model.priceText(entry.price, currency: entry.currency))
                                    .font(.body.weight(.semibold))
                                    .monospacedDigit()
                                Text(verbatim: model.unitPriceText(entry)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .navigationTitle(storeTitle(for: line, directory: directory))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("common.close") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var chart: some View {
        Chart(entries) { entry in
            LineMark(x: .value(Text("price.axis.date"), entry.date),
                     y: .value(Text("price.axis.unitPrice"), NSDecimalNumber(decimal: entry.unitPrice).doubleValue))
                .interpolationMethod(.monotone)
            PointMark(x: .value(Text("price.axis.date"), entry.date),
                      y: .value(Text("price.axis.unitPrice"), NSDecimalNumber(decimal: entry.unitPrice).doubleValue))
                .accessibilityLabel(Text(entry.date, format: .dateTime.year().month().day()))
                .accessibilityValue(Text(verbatim: model.unitPriceText(entry)))
        }
        .chartYAxisLabel(line.latest.currency)
        .foregroundStyle(Palette.mocha600)
        .animation(reduceMotion ? nil : .default, value: entries.count)
    }
}
