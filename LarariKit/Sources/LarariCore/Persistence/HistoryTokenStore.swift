import CoreData
import Foundation

/// The last consumed history token per store, archived into the injected UserDefaults (the app passes AppModel.appDefaults).
@MainActor
public final class HistoryTokenStore {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public func token(for storeIdentifier: String) -> NSPersistentHistoryToken? {
        guard let data = defaults.data(forKey: key(storeIdentifier)) else { return nil }
        return try? NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: data)
    }

    public func setToken(_ token: NSPersistentHistoryToken?, for storeIdentifier: String) {
        guard let token,
              let data = try? NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true) else {
            defaults.removeObject(forKey: key(storeIdentifier))
            return
        }
        defaults.set(data, forKey: key(storeIdentifier))
    }

    private func key(_ storeIdentifier: String) -> String { "historyToken.\(storeIdentifier)" }
}
