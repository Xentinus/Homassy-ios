import CoreData
import Foundation
import HomassyShared

/// Where a Home Screen quick action or a notification tap takes the user (N-02). HomassyCore decides which
/// destination an input means; the app maps it onto tabs, filters and sheets (`AppRouter`).
public enum AppDestination: Equatable, Sendable {
    /// The Inventory tab at its root, in whatever grouping is remembered.
    case inventory(spaceID: UUID?)
    /// The Inventory tab grouped by expiry (the "Expiring soon" quick action and the expiry notifications, P2-08e).
    case inventoryExpiring(spaceID: UUID?)
    /// The Shopping home with its current filter.
    case shopping(spaceID: UUID?)
    /// The Shopping home filtered to one list.
    case shoppingList(spaceID: UUID, listID: UUID)
    /// The Shopping home grouped by store, filter "Mind" (a Live Activity tap, N-04).
    case shoppingByStore(spaceID: UUID)
    /// The Shopping home with the add sheet open on that list.
    case addToShoppingList(spaceID: UUID, listID: UUID)
    /// The Inventory tab with the barcode scanner open.
    case scanBarcode
}

extension AppDestination {
    /// A `homassy://` link from the Live Activity (N-04) or a widget (N-05).
    public init(_ link: HomassyDeepLink) {
        switch link {
        case let .inventory(spaceID): self = .inventory(spaceID: spaceID)
        case let .shoppingStore(spaceID, _): self = .shoppingByStore(spaceID: spaceID)
        }
    }
}

/// A shopping list by its space and its own public IDs, as stored for "the last used list".
public struct ShoppingListReference: Equatable, Sendable {
    public let spaceID: UUID
    public let listID: UUID

    public init(spaceID: UUID, listID: UUID) {
        self.spaceID = spaceID
        self.listID = listID
    }
}

extension ServiceContainer {
    /// The list a quick action refers to, if it still exists.
    public func shoppingList(_ reference: ShoppingListReference) -> ShoppingList? {
        guard let space = space(reference.spaceID) else { return nil }
        return (try? shopping.lists(in: space))?.first { $0.publicId == reference.listID }
    }

    /// A destination the app can show now: a deleted list falls back to its space's Shopping home, a deleted space
    /// to the current one, and a list the user may not edit opens without the add sheet.
    public func validated(_ destination: AppDestination) -> AppDestination {
        switch destination {
        case .inventory(let spaceID?) where space(spaceID) == nil:
            return .inventory(spaceID: nil)
        case .inventoryExpiring(let spaceID?) where space(spaceID) == nil:
            return .inventoryExpiring(spaceID: nil)
        case .shopping(let spaceID?) where space(spaceID) == nil:
            return .shopping(spaceID: nil)
        case let .shoppingList(spaceID, listID):
            guard space(spaceID) != nil else { return .shopping(spaceID: nil) }
            return shoppingList(ShoppingListReference(spaceID: spaceID, listID: listID)) == nil
                ? .shopping(spaceID: spaceID) : destination
        case let .addToShoppingList(spaceID, listID):
            guard space(spaceID) != nil else { return .shopping(spaceID: nil) }
            guard let found = shoppingList(ShoppingListReference(spaceID: spaceID, listID: listID)) else {
                return .shopping(spaceID: spaceID)
            }
            guard let owner = found.space, shopping.canEdit(owner) else {
                return .shoppingList(spaceID: spaceID, listID: listID)
            }
            return destination
        case let .shoppingByStore(spaceID):
            return space(spaceID) == nil ? .shopping(spaceID: nil) : destination
        case .inventory, .inventoryExpiring, .shopping, .scanBarcode:
            return destination
        }
    }

    private func space(_ id: UUID) -> Space? {
        (try? spaceStore.allSpaces())?.first { $0.publicId == id }
    }
}
