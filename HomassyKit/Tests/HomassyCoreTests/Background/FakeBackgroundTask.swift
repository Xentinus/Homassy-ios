import Foundation
import Synchronization
@testable import HomassyCore

/// Records completions like `BGTask.setTaskCompleted(success:)` and fires the expiration handler from a background
/// thread, the way the system does.
final class FakeBackgroundTask: BackgroundTaskHandle {
    private let handler = Mutex<(@Sendable () -> Void)?>(nil)
    private let recorded = Mutex<[Bool]>([])

    var completions: [Bool] { recorded.withLock { $0 } }

    func setExpirationHandler(_ handler: @escaping @Sendable () -> Void) {
        self.handler.withLock { $0 = handler }
    }

    func setTaskCompleted(success: Bool) {
        recorded.withLock { $0.append(success) }
    }

    func fireExpiration() async {
        let handler = self.handler.withLock { $0 }
        await Task.detached { handler?() }.value
    }
}
