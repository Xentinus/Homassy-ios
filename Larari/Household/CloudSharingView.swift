import CloudKit
import LarariCore
import SwiftUI
import UIKit

struct SharingPresentation: Identifiable {
    let id = UUID()
    let share: CKShare
}

/// The system sharing UI (participants, Add People, permissions; Remove Me for a participant).
struct CloudSharingView: UIViewControllerRepresentable {
    let share: CKShare
    let space: Space
    let sharing: SharingService
    let onError: @MainActor (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(space: space, title: space.name, zoneID: share.recordID.zoneID,
                    wasOwner: sharing.role(for: space) == .owner, sharing: sharing, onError: onError)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(share: share, container: CKContainer(identifier: AppModel.containerIdentifier))
        controller.availablePermissions = [.allowPrivate, .allowReadOnly, .allowReadWrite]
        controller.delegate = context.coordinator
        controller.modalPresentationStyle = .formSheet
        return controller
    }

    func updateUIViewController(_ controller: UICloudSharingController, context: Context) {}

    @MainActor
    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let space: Space
        private let title: String
        private let zoneID: CKRecordZone.ID
        private let wasOwner: Bool
        private let sharing: SharingService
        private let onError: @MainActor (String) -> Void

        init(space: Space, title: String, zoneID: CKRecordZone.ID, wasOwner: Bool,
             sharing: SharingService, onError: @escaping @MainActor (String) -> Void) {
            self.space = space
            self.title = title
            self.zoneID = zoneID
            self.wasOwner = wasOwner
            self.sharing = sharing
            self.onError = onError
        }

        func itemTitle(for csc: UICloudSharingController) -> String? { title }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: Error) {
            onError(error.localizedDescription)
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            guard let share = csc.share else { return }
            Task {
                do { try await sharing.saveUpdatedShare(share, for: space) }
                catch { onError(error.localizedDescription) }
            }
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            Task {
                do { try await sharing.sharingStopped(for: space, zoneID: zoneID, wasOwner: wasOwner) }
                catch { onError(error.localizedDescription) }
            }
        }
    }
}
