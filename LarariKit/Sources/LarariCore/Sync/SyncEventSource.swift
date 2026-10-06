import CoreData
import Foundation

public enum SyncEventSource {
    /// Maps eventChangedNotification to Sendable snapshots on CloudKit's posting queue.
    @MainActor
    public static func events(from container: NSPersistentCloudKitContainer) -> AsyncStream<SyncEventSnapshot> {
        AsyncStream { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: NSPersistentCloudKitContainer.eventChangedNotification,
                object: container,
                queue: nil
            ) { @Sendable notification in
                guard let event = notification.userInfo?[NSPersistentCloudKitContainer.eventNotificationUserInfoKey]
                        as? NSPersistentCloudKitContainer.Event,
                      let snapshot = SyncEventSnapshot(event: event) else { return }
                continuation.yield(snapshot)
            }
            let token = UncheckedSendable(value: observer)
            continuation.onTermination = { @Sendable _ in
                NotificationCenter.default.removeObserver(token.value)
            }
        }
    }
}
