import CloudKit
import CoreData
import Foundation
@testable import LarariCore

/// In-memory store with a bootstrapped Personal space. Every service test builds one.
@MainActor
struct ServiceTestEnvironment {
    struct NoShares: ShareLookup {
        @MainActor func share(for space: Space) -> CKShare? { nil }
    }

    static let user = "_testUser"
    static let otherUser = "_otherUser"

    let persistence: PersistenceController
    let spaceStore: SpaceStore
    let personal: Space
    var context: NSManagedObjectContext { persistence.viewContext }

    init() throws {
        persistence = try PersistenceController(mode: .inMemory)
        spaceStore = SpaceStore(persistence: persistence, sharing: NoShares())
        personal = try spaceStore.bootstrapPersonalSpace(userRecordName: Self.user)
    }

    /// A second, owned household in the private store (P5 adds the real creation flow).
    func makeHousehold(_ name: String = "Home") throws -> Space {
        let space = spaceStore.insert(Space.self, in: personal, by: Self.user)
        space.name = name
        space.kind = .household
        try context.save()
        return space
    }

    func productService(user: String = ServiceTestEnvironment.user,
                        canEdit: @escaping @MainActor (Space) -> Bool = { _ in true }) -> ProductService {
        ProductService(spaceStore: spaceStore, context: context, userRecordName: user, canEdit: canEdit)
    }

    @discardableResult
    func makeProduct(_ name: String, in space: Space? = nil, brand: String = "", category: String = "",
                     barcode: String = "", unit: MeasureUnit = .piece, image: Data? = nil) async throws -> Product {
        try await productService().create(in: space ?? personal, draft: ProductDraft(
            name: name, brand: brand, category: category, barcode: barcode, defaultUnit: unit, imageData: image))
    }

    func count<T: NSManagedObject>(_ type: T.Type, where predicate: NSPredicate? = nil) throws -> Int {
        try context.countEntities(type, where: predicate)
    }
}
