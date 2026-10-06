import Foundation
import Testing
@testable import LarariCore

/// N-03: the value a list or product window is opened with. SwiftUI stores it to restore the window, so its JSON
/// shape must stay stable across versions.
@Suite("WindowRoute")
struct WindowRouteTests {
    private let id = UUID(uuidString: "6F1C1E0A-3B7C-4C31-9F0E-2B6C8D1A5E42")!

    private func json(_ route: WindowRoute) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try encoder.encode(route), as: UTF8.self)
    }

    @Test func encodesAStableKindAndID() throws {
        #expect(try json(.shoppingList(id)) == #"{"id":"6F1C1E0A-3B7C-4C31-9F0E-2B6C8D1A5E42","kind":"shoppingList"}"#)
        #expect(try json(.product(id)) == #"{"id":"6F1C1E0A-3B7C-4C31-9F0E-2B6C8D1A5E42","kind":"product"}"#)
    }

    @Test func roundTripsThroughJSON() throws {
        for route in [WindowRoute.shoppingList(UUID()), .product(UUID())] {
            let data = try JSONEncoder().encode(route)
            #expect(try JSONDecoder().decode(WindowRoute.self, from: data) == route)
        }
    }

    @Test func anUnknownKindDoesNotDecode() {
        let data = Data(#"{"id":"6F1C1E0A-3B7C-4C31-9F0E-2B6C8D1A5E42","kind":"recipe"}"#.utf8)
        #expect(throws: DecodingError.self) { try JSONDecoder().decode(WindowRoute.self, from: data) }
    }

    @Test func exposesTheItemID() {
        #expect(WindowRoute.shoppingList(id).id == id)
        #expect(WindowRoute.product(id).id == id)
    }

    /// `openWindow(value:)` brings an existing window with an equal value forward instead of opening a second one.
    @Test func equalRoutesAreOneWindow() {
        #expect(Set([WindowRoute.product(id), .product(id)]).count == 1)
        #expect(WindowRoute.product(id) != .shoppingList(id))
    }

    @Test func userInfoRoundTrips() {
        for route in [WindowRoute.shoppingList(UUID()), .product(UUID())] {
            #expect(WindowRoute(userInfo: route.userInfo) == route)
        }
        #expect(WindowRoute.shoppingList(id).userInfo == ["kind": "shoppingList", "id": id.uuidString])
    }

    @Test func incompleteUserInfoIsRejected() {
        #expect(WindowRoute(userInfo: [:]) == nil)
        #expect(WindowRoute(userInfo: ["kind": "product", "id": "not-a-uuid"]) == nil)
        #expect(WindowRoute(userInfo: ["kind": "recipe", "id": UUID().uuidString]) == nil)
    }

    @Test func activityTypeIsTheDeclaredOne() {
        #expect(WindowRoute.activityType == "app.larari.window")    // Info.plist NSUserActivityTypes (Task 8)
    }
}
