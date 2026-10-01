import SwiftUI

/// The paid amount and its currency on one row; stacked at accessibility sizes, where a 72 pt currency field would
/// cut "USD" to "U…" (X-04). Used by the add-stock details and the purchase sheet.
struct PriceFieldRow: View {
    @Binding var price: String
    @Binding var currency: String
    let priceIdentifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let stacked = dynamicTypeSize.isAccessibilitySize
        let layout = stacked ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        layout {
            TextField("shopping.purchase.pricePaid", text: $price)
                .keyboardType(.decimalPad)
                .accessibilityIdentifier(priceIdentifier)
            TextField("stock.currency", text: $currency)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .multilineTextAlignment(stacked ? .leading : .trailing)
                .frame(maxWidth: stacked ? .infinity : 72)
        }
    }
}
