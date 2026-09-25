import CloudKit
import UIKit

/// SwiftUI still owns the window; this class only receives CloudKit share acceptances.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let metadata = connectionOptions.cloudKitShareMetadata {       // cold start from a link
            ShareInvitationInbox.shared.receive(metadata)
        }
    }

    func windowScene(_ windowScene: UIWindowScene, userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata) {
        ShareInvitationInbox.shared.receive(cloudKitShareMetadata)          // app already running
    }
}
