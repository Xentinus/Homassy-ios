import CoreData
import Foundation
import Testing
@testable import HomassyCore

@MainActor
final class BatchSink {
    var batches: [HistoryBatch] = []
}

@MainActor
struct RemoteChangeObserverTests {
    @Test func remoteChangeNotificationDeliversAForeignBatch() async throws {
        let (container, store) = try HistoryTestContainer.make()
        let defaults = UserDefaults(suiteName: "RemoteChangeObserverTests-\(UUID().uuidString)")!
        let processor = HistoryProcessor(container: container, tokens: HistoryTokenStore(defaults: defaults),
                                         currentUserRecordName: "_me", deduplicateStore: store)
        _ = try processor.process(store: store)
        let sink = BatchSink()
        let observer = RemoteChangeObserver(container: container, processor: processor) { batch in
            sink.batches.append(batch)
        }
        observer.start()
        defer { observer.stop() }

        let id = try HistoryTestContainer.importProduct(into: container, name: "Milk", updatedBy: "_anna")
        NotificationCenter.default.post(name: .NSPersistentStoreRemoteChange,
                                        object: container.persistentStoreCoordinator,
                                        userInfo: [NSStoreUUIDKey: store.identifier ?? ""])

        for _ in 0..<100 where sink.batches.flatMap(\.foreignChanges).isEmpty {
            try await Task.sleep(for: .milliseconds(20))
        }
        #expect(sink.batches.flatMap(\.foreignChanges).map(\.publicId) == [id])
    }
}
