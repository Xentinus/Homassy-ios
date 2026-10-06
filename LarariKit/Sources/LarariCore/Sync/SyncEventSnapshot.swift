import CloudKit
import CoreData
import Foundation

public struct ZoneReference: Sendable, Hashable {
    public let zoneName: String
    public let ownerName: String

    public init(zoneName: String, ownerName: String) {
        self.zoneName = zoneName
        self.ownerName = ownerName
    }

    public init(_ zoneID: CKRecordZone.ID) {
        self.init(zoneName: zoneID.zoneName, ownerName: zoneID.ownerName)
    }
}

public struct SyncFailureInfo: Sendable, Equatable {
    public let code: Int
    public let isCloudKit: Bool
    public let partialCodes: [Int]
    public let affectedZones: [ZoneReference]

    public init(code: Int, isCloudKit: Bool, partialCodes: [Int] = [], affectedZones: [ZoneReference] = []) {
        self.code = code
        self.isCloudKit = isCloudKit
        self.partialCodes = partialCodes
        self.affectedZones = affectedZones
    }

    /// Unwraps NSUnderlyingErrorKey chains (Core Data wraps CloudKit errors) and partial failures.
    public init(error: Error) {
        var nsError = error as NSError
        var depth = 0
        while nsError.domain != CKErrorDomain, depth < 4,
              let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            nsError = underlying
            depth += 1
        }
        guard nsError.domain == CKErrorDomain else {
            self.init(code: (error as NSError).code, isCloudKit: false)
            return
        }
        let partial = (nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: Error]) ?? [:]
        let entries = partial.sorted { String(describing: $0.key) < String(describing: $1.key) }
        let zones: [ZoneReference] = entries.compactMap { key, _ in
            if let zoneID = key.base as? CKRecordZone.ID { return ZoneReference(zoneID) }
            if let recordID = key.base as? CKRecord.ID { return ZoneReference(recordID.zoneID) }
            return nil
        }
        self.init(code: nsError.code, isCloudKit: true,
                  partialCodes: entries.map { ($0.value as NSError).code },
                  affectedZones: Array(Set(zones)).sorted { $0.zoneName < $1.zoneName })
    }
}

public struct SyncEventSnapshot: Sendable, Equatable {
    public enum Kind: Sendable, Equatable { case setup, importing, exporting }

    public let id: UUID
    public let storeIdentifier: String
    public let kind: Kind
    public let startDate: Date
    public let endDate: Date?
    public let succeeded: Bool
    public let failure: SyncFailureInfo?

    public init(id: UUID, storeIdentifier: String, kind: Kind, startDate: Date, endDate: Date?,
                succeeded: Bool, failure: SyncFailureInfo?) {
        self.id = id
        self.storeIdentifier = storeIdentifier
        self.kind = kind
        self.startDate = startDate
        self.endDate = endDate
        self.succeeded = succeeded
        self.failure = failure
    }

    public init?(event: NSPersistentCloudKitContainer.Event) {
        let kind: Kind
        switch event.type {
        case .setup: kind = .setup
        case .import: kind = .importing
        case .export: kind = .exporting
        @unknown default: return nil
        }
        self.init(id: event.identifier, storeIdentifier: event.storeIdentifier, kind: kind,
                  startDate: event.startDate, endDate: event.endDate, succeeded: event.succeeded,
                  failure: event.error.map(SyncFailureInfo.init(error:)))
    }
}
