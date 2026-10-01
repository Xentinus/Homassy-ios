import HomassyCore
import SwiftUI

/// Every history event of a product, newest first, in month sections (P2-07a, 3A, the Wallet "all transactions"
/// page). Pushed from the detail's "Az összes előzmény".
struct ProductHistoryView: View {
    let model: ProductDetailModel

    var body: some View {
        Group {
            if model.fields == nil {
                ContentUnavailableView("product.detail.notFound", systemImage: "questionmark.square.dashed")
            } else {
                List {
                    ForEach(model.historyByMonth) { month in
                        Section {
                            ForEach(month.rows) { HistoryEventRow(row: $0) }
                        } header: {
                            if !month.title.isEmpty { Text(verbatim: month.title) }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .accessibilityIdentifier("history.page")
            }
        }
        .navigationTitle(Text("product.detail.historySection"))
        .navigationBarTitleDisplayMode(.inline)
    }
}
