import CloudKit
import UIKit

/// SwiftUI still owns the windows; this class only receives CloudKit share acceptances and Home Screen quick actions.
/// AppDelegate gives every window's scene one (main windows and N-03 list and product windows), so an invitation
/// arrives whichever window the system picks.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {       // cold start from a link
            ShareInvitationInbox.shared.receive(metadata)
        }
        if let shortcut = connectionOptions.shortcutItem {                // cold start from a quick action (N-02)
            _ = QuickActions.handle(shortcut)
        }
#if DEBUG
        if UITestHooks.increasesContrast, let windowScene = scene as? UIWindowScene {
            windowScene.traitOverrides.accessibilityContrast = .high
        }
#endif
    }

    /// Warm start from a quick action (N-02). The completion-handler form, never the async one (see 2732862).
    func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem,
                     completionHandler: @escaping (Bool) -> Void) {
        completionHandler(QuickActions.handle(shortcutItem))
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInvitationInbox.shared.receive(cloudKitShareMetadata)          // app already running
    }
}
