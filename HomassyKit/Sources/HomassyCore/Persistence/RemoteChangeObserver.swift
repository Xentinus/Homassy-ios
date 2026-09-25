import CoreData
import Foundation
import os

/// Serialises NSPersistentStoreRemoteChange notifications into HistoryProcessor runs.
@MainActor
public final class RemoteChangeObserver {
    private let container: NSPersistentContainer
    private let processor: HistoryProcessor
    private let onBatch: @MainActor (HistoryBatch) async -> Void
    private var observer: (any NSObjectProtocol)?
    private var task: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.homassy.app", category: "RemoteChanges")

    public init(container: NSPersistentContainer, processor: HistoryProcessor,
                onBatch: @escaping @MainActor (HistoryBatch) async -> Void) {
        self.container = container
        self.processor = processor
        self.onBatch = onBatch
    }

    public func start() {
        guard task == nil else { return }
        let (stream, continuation) = AsyncStream.makeStream(of: String?.self)
        observer = NotificationCenter.default.addObserver(
            forName: .NSPersistentStoreRemoteChange,
            object: container.persistentStoreCoordinator,
            queue: nil
        ) { @Sendable notification in
            continuation.yield(notification.userInfo?[NSStoreUUIDKey] as? String)
        }
        continuation.yield(nil)              // catch up on every store once at start
        task = Task { [weak self] in
            for await storeID in stream {
                guard let self else { return }
                await self.handle(storeID: storeID)
            }
        }
    }

    public func stop() {
        if let observer { NotificationCenter.default.removeObserver(observer) }
        observer = nil
        task?.cancel()
        task = nil
    }

    private func handle(storeID: String?) async {
        let stores = container.persistentStoreCoordinator.persistentStores
            .filter { storeID == nil || $0.identifier == storeID }
        for store in stores {
            do {
                let batch = try processor.process(store: store)
                if !batch.isEmpty { await onBatch(batch) }
            } catch {
                logger.error("History processing failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
