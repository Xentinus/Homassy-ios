import CloudKit
import CoreData
import Foundation

/// Answers "which CKShare, if any, covers this space". The real implementation wraps the container;
/// tests use a fake.
public protocol ShareLookup: Sendable {
    @MainActor func share(for space: Space) -> CKShare?
}

/// Share lookup backed by `NSPersistentCloudKitContainer.fetchShares(matching:)`.
@MainActor
public final class ContainerShareLookup: ShareLookup {
    private let container: NSPersistentCloudKitContainer

    public init(container: NSPersistentCloudKitContainer) {
        self.container = container
    }

    public func share(for space: Space) -> CKShare? {
        guard !space.objectID.isTemporaryID else { return nil }
        let shares = try? container.fetchShares(matching: [space.objectID])
        return shares?[space.objectID]
    }
}
