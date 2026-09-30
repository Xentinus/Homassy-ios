import Combine
import CoreData
import HomassyCore
import SwiftUI

/// Keeps the shopping Live Activity current (N-04): evaluates on launch, on every foreground and when an arrival
/// notification was tapped (D9 B: that is how it starts), and refreshes after every save. Remote changes come from
/// AppModel's RemoteChangeObserver.
private struct ShoppingActivityModifier: ViewModifier {
    let app: AppModel
    let coordinator: ShoppingActivityCoordinator
    let context: NSManagedObjectContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var router = AppRouter.shared

    func body(content: Content) -> some View {
        content
            .task { await app.evaluateShoppingActivity() }
            .onChange(of: scenePhase) {
                if scenePhase == .active { Task { await app.evaluateShoppingActivity() } }
            }
            .onChange(of: router.arrivalBranch) {
                Task { await app.evaluateShoppingActivity() }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification,
                                                            object: context)
                        .receive(on: DispatchQueue.main)) { _ in
                coordinator.scheduleRefresh()
            }
    }
}

extension View {
    func shoppingActivity(_ app: AppModel, coordinator: ShoppingActivityCoordinator,
                          context: NSManagedObjectContext) -> some View {
        modifier(ShoppingActivityModifier(app: app, coordinator: coordinator, context: context))
    }
}
