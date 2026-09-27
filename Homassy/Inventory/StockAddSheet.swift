import HomassyCore
import SwiftUI

/// Adding stock (P2-08a): the searchable product list first when the product is unknown, then the details with
/// the lots. With a known product (barcode) or when editing, the details are the root.
struct StockAddSheet: View {
    @State private var form: StockFormModel
    @State private var picker: ProductPickerModel?
    @State private var path: [UUID] = []
    @Environment(\.dismiss) private var dismiss

    init(form: StockFormModel, picker: ProductPickerModel?) {
        _form = State(initialValue: form)
        _picker = State(initialValue: picker)
    }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let picker {
                    ProductPickerView(model: picker, onCancel: { dismiss() }) { id in
                        form.setProduct(id)
                        path = [id]
                    }
                } else {
                    StockDetailsView(form: form, showsCancel: true) { dismiss() }
                }
            }
            .navigationDestination(for: UUID.self) { _ in
                StockDetailsView(form: form, showsCancel: false) { dismiss() }
            }
        }
        .presentationDetents([.large])
    }
}

extension StockAddSheet {
    /// Inventory `+`: pick a product first.
    static func picking(in space: Space, services: ServiceContainer) -> StockAddSheet {
        StockAddSheet(form: .adding(in: space, productID: nil, services: services),
                      picker: ProductPickerModel(space: space, products: services.products,
                                                 inventory: services.inventory, pending: services.pendingDeletions))
    }

    /// A known product (the barcode flow).
    static func adding(_ productID: UUID, in space: Space, services: ServiceContainer) -> StockAddSheet {
        StockAddSheet(form: .adding(in: space, productID: productID, services: services), picker: nil)
    }
}

extension StockFormModel {
    static func adding(in space: Space, productID: UUID?, services: ServiceContainer) -> StockFormModel {
        StockFormModel(mode: .add(space, productID: productID), inventory: services.inventory,
                       products: services.products, storage: services.storageLocations,
                       locations: services.shoppingLocations)
    }
}

#if DEBUG
#Preview("Picker") {
    let model = AppModel.preview()
    let services = model.services!
    StockAddSheet.picking(in: model.personalSpace!, services: services)
        .environment(services)
        .environment(services.storeDirectory)
}

#Preview("Details, landscape", traits: .landscapeLeft) {
    let model = AppModel.preview()
    let services = model.services!
    let space = model.personalSpace!
    let id = ((try? services.products.products(in: space)) ?? []).first?.publicId ?? UUID()
    StockAddSheet.adding(id, in: space, services: services)
        .environment(services)
        .environment(services.storeDirectory)
}
#endif
