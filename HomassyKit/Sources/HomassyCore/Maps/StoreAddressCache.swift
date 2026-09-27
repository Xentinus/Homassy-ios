import Foundation
import Observation

/// Store addresses by `mapItemIdentifier` (P2-08b), kept in a JSON file on this device. It is not in Core Data,
/// because the programmatic model has no versioning. A missing or unreadable file starts empty.
@MainActor
@Observable
public final class StoreAddressCache {
    public static var defaultURL: URL {
        StoreMode.localDevelopmentDirectory.appending(path: "store-addresses.json")
    }

    private var addresses: [String: StoreAddress]
    @ObservationIgnored private let fileURL: URL?

    /// Nil keeps the addresses in memory only (tests, UI tests).
    public init(fileURL: URL?) {
        self.fileURL = fileURL
        if let fileURL, let data = try? Data(contentsOf: fileURL),
           let decoded = try? JSONDecoder().decode([String: StoreAddress].self, from: data) {
            addresses = decoded
        } else {
            addresses = [:]
        }
    }

    public func address(for identifier: String) -> StoreAddress? { addresses[identifier] }

    public func set(_ address: StoreAddress, for identifier: String) {
        guard addresses[identifier] != address else { return }
        addresses[identifier] = address
        guard let fileURL else { return }
        try? FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(addresses).write(to: fileURL, options: .atomic)
    }
}
