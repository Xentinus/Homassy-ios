import LarariCore
import SwiftUI

/// The detail's "Adatok" section (P2-07a): unit, category and notes as labelled rows, like a contact's fields.
/// The barcode sits in the header (5A), not here.
struct ProductFactsSection: View {
    let fields: ProductFields

    var body: some View {
        Section("product.detail.facts") {
            LabeledContent("product.field.unit") { Text(verbatim: fields.unitName) }
            if let category = fields.category, !category.isEmpty {
                LabeledContent("product.field.category") { Text(verbatim: category) }
            }
            if let notes = fields.notes, !notes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("product.field.notes").font(.subheadline).foregroundStyle(.secondary)
                    Text(verbatim: notes)
                }
                .accessibilityElement(children: .combine)
            }
        }
        .accessibilityIdentifier("product.facts")
    }
}
