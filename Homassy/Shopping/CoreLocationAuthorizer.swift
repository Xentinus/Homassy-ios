import CoreLocation
import HomassyCore

/// When In Use only. Never requests Always and never monitors in the background.
@MainActor
final class CoreLocationAuthorizer: NSObject, LocationAuthorizing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<LocationAccess, Never>] = []
    /// Called whenever the authorization changes (P4-06 refreshes the store reminders then).
    var onAccessChange: (@MainActor () -> Void)?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var access: LocationAccess {
        switch manager.authorizationStatus {
        case .notDetermined: .notDetermined
        case .authorizedWhenInUse, .authorizedAlways: .authorized
        default: .denied
        }
    }

    func requestWhenInUse() async -> LocationAccess {
        guard access == .notDetermined else { return access }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
            manager.requestWhenInUseAuthorization()
        }
    }

    func currentCoordinate() async -> Coordinate? {
        guard access == .authorized else { return nil }
        do {
            for try await update in CLLocationUpdate.liveUpdates() {
                if let location = update.location {
                    return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
                }
                if update.authorizationDenied || update.authorizationDeniedGlobally { return nil }
            }
        } catch {
            return nil
        }
        return nil
    }

    /// The position Core Location already has, if it is at most a day old (N-01). Reading it starts no updates, so
    /// it works in a background launch with When In Use access.
    var lastKnownCoordinate: Coordinate? {
        guard access == .authorized, let location = manager.location,
              location.timestamp.timeIntervalSinceNow > -24 * 60 * 60 else { return nil }
        return Coordinate(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let current = self.access
            guard current != .notDetermined else { return }
            let pending = self.waiters
            self.waiters.removeAll()
            for waiter in pending { waiter.resume(returning: current) }
            self.onAccessChange?()
        }
    }
}
