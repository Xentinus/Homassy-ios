import Combine
import CoreData
import LarariCore
import SwiftUI

/// Keeps the store reminders current (P4-06): on foreground (and so after the Settings switch changed) and after
/// shopping saves. Remote changes come from AppModel's RemoteChangeObserver.
private struct StoreRemindersModifier: ViewModifier {
    let coordinator: StoreReminderCoordinator
    let context: NSManagedObjectContext
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content
            .task { coordinator.scheduleRefresh(.foreground) }
            .onChange(of: scenePhase) {
                if scenePhase == .active { coordinator.scheduleRefresh(.foreground) }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSManagedObjectContext.didSaveObjectsNotification,
                                                            object: context)
                        .receive(on: DispatchQueue.main)) { notification in
                if Self.touchesShopping(notification) { coordinator.scheduleRefresh(.localSave) }
            }
    }

    private static func touchesShopping(_ notification: Notification) -> Bool {
        let keys = [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey]
        return keys.contains { key in
            (notification.userInfo?[key] as? Set<NSManagedObject>)?.contains {
                $0 is ShoppingListItem || $0 is ShoppingLocation || $0 is ShoppingList
            } ?? false
        }
    }
}

extension View {
    func storeReminders(_ coordinator: StoreReminderCoordinator, context: NSManagedObjectContext) -> some View {
        modifier(StoreRemindersModifier(coordinator: coordinator, context: context))
    }
}
