import Combine
import CoreData
import LarariCore
import SwiftUI

/// Keeps the 07:00 summaries and the badge current: on foreground, after local saves, after remote changes.
private struct ExpiryNotificationsModifier: ViewModifier {
    let coordinator: ExpiryNotificationCoordinator
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
                        .receive(on: DispatchQueue.main)) { _ in
                coordinator.scheduleRefresh(.localSave)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)
                        .receive(on: DispatchQueue.main)) { _ in
                coordinator.scheduleRefresh(.remoteChange)
            }
    }
}

extension View {
    func expiryNotifications(_ coordinator: ExpiryNotificationCoordinator, context: NSManagedObjectContext) -> some View {
        modifier(ExpiryNotificationsModifier(coordinator: coordinator, context: context))
    }
}
