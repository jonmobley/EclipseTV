//
//  CloudKitShareCoordinator.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import UIKit
import os.log

/// Presents `UICloudSharingController` for a Show (share root + child MediaItems).
@MainActor
final class CloudKitShareCoordinator: NSObject {

    private let container: CKContainer
    private let database: CKDatabase
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CloudKitShare"
    )
    /// Called after a `CKShare` exists on the server for this Show.
    var onShareRootEstablished: ((UUID) -> Void)?
    /// Called when the user stops sharing the current Show.
    var onShareRootRemoved: ((UUID) -> Void)?
    private var currentShareShowId: UUID?

    init(container: CKContainer, database: CKDatabase) {
        self.container = container
        self.database = database
    }

    /// Loads or creates a `CKShare` for `showId` and presents the system UI.
    func presentShareUI(forShowId showId: UUID, from presenter: UIViewController) {
        guard let album = LocalAlbumStore.shared.album(id: showId) else { return }
        Task {
            do {
                try await presentShareUI(album: album, from: presenter)
            } catch {
                presentError(error, from: presenter)
            }
        }
    }

    private func presentShareUI(
        album: LocalAlbum,
        from presenter: UIViewController
    ) async throws {
        currentShareShowId = album.id
        let recordID = CloudKitSchema.showRecordID(for: album.id)
        let root: CKRecord
        do {
            root = try await database.record(for: recordID)
        } catch {
            // Ensure the Show exists in CloudKit before sharing.
            let created = CloudKitRecordMapper.makeShowRecord(from: album)
            root = try await database.save(created)
        }

        if let existingShare = root.share,
           let shareRecord = try? await database.record(for: existingShare.recordID),
           let share = shareRecord as? CKShare {
            onShareRootEstablished?(album.id)
            present(share: share, root: root, from: presenter)
            return
        }
        createAndPresent(root: root, album: album, from: presenter)
    }

    private func createAndPresent(
        root: CKRecord,
        album: LocalAlbum,
        from presenter: UIViewController
    ) {
        let share = CKShare(rootRecord: root)
        share[CKShare.SystemFieldKey.title] = album.name as CKRecordValue
        share.publicPermission = .readOnly

        let op = CKModifyRecordsOperation(recordsToSave: [root, share], recordIDsToDelete: nil)
        op.modifyRecordsResultBlock = { result in
            Task { @MainActor in
                switch result {
                case .success:
                    self.onShareRootEstablished?(album.id)
                    self.present(share: share, root: root, from: presenter)
                case .failure(let error):
                    self.presentError(error, from: presenter)
                }
            }
        }
        database.add(op)
    }

    private func present(share: CKShare, root: CKRecord, from presenter: UIViewController) {
        let controller = UICloudSharingController(share: share, container: container)
        controller.delegate = self
        controller.availablePermissions = [.allowReadOnly, .allowReadWrite, .allowPrivate]
        if let pop = controller.popoverPresentationController {
            pop.sourceView = presenter.view
            pop.sourceRect = CGRect(
                x: presenter.view.bounds.midX,
                y: presenter.view.bounds.midY,
                width: 1,
                height: 1
            )
        }
        presenter.present(controller, animated: true)
        _ = root
    }

    private func presentError(_ error: Error, from presenter: UIViewController) {
        logger.error("Share failed: \(error.localizedDescription)")
        let alert = UIAlertController(
            title: "Unable to Share",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        presenter.present(alert, animated: true)
    }
}

// MARK: - UICloudSharingControllerDelegate

extension CloudKitShareCoordinator: UICloudSharingControllerDelegate {
    func cloudSharingController(
        _ csc: UICloudSharingController,
        failedToSaveShareWithError error: Error
    ) {
        logger.error("failedToSaveShare: \(error.localizedDescription)")
    }

    func itemTitle(for csc: UICloudSharingController) -> String? {
        "Eclipse Show"
    }

    func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
        if let id = currentShareShowId {
            onShareRootEstablished?(id)
        }
    }

    func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
        if let id = currentShareShowId {
            onShareRootRemoved?(id)
        }
    }
}
