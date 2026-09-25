import CoreLocation
import HomassyCore

/// When In Use only. Never requests Always and never monitors in the background.
@MainActor
final class CoreLocationAuthorizer: NSObject, LocationAuthorizing, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiters: [CheckedContinuation<LocationAccess, Never>] = []

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

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        MainActor.assumeIsolated {
            let current = self.access
            guard current != .notDetermined else { return }
            let pending = self.waiters
            self.waiters.removeAll()
            for waiter in pending { waiter.resume(returning: current) }
        }
    }
}
