//
//  CloudKitSharedSyncHost.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log

/// Second `CKSyncEngine` on the shared database for Shows accepted via `CKShare`.
///
/// Phase 1 ingests shared Show + MediaItem records into the local stores as
/// read-only mirrors (same models). Edits to shared Shows still go through the
/// private engine when the user is the owner.
@MainActor
final class CloudKitSharedSyncHost: NSObject, CKSyncEngineDelegate {

    private let container: CKContainer
    private var engine: CKSyncEngine?
    private let stateKey = "EclipseTV.cloudKit.sharedSyncEngineState"
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CloudKitSharedSync"
    )
    private var didStart = false

    init(container: CKContainer) {
        self.container = container
    }

    /// Starts the shared-database engine when an iCloud account is available.
    func start() {
        guard !didStart else { return }
        didStart = true
        var serialization: CKSyncEngine.State.Serialization?
        if let data = UserDefaults.standard.data(forKey: stateKey) {
            serialization = try? JSONDecoder().decode(
                CKSyncEngine.State.Serialization.self,
                from: data
            )
        }
        let configuration = CKSyncEngine.Configuration(
            database: container.sharedCloudDatabase,
            stateSerialization: serialization,
            delegate: self
        )
        engine = CKSyncEngine(configuration)
        logger.info("Shared CKSyncEngine started")
    }

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            if let data = try? JSONEncoder().encode(update.stateSerialization) {
                UserDefaults.standard.set(data, forKey: stateKey)
            }
        case .fetchedRecordZoneChanges(let changes):
            // Applying a shared record writes to the same local stores the private
            // engine watches. Without this flag their didChange notifications look like
            // local edits and fork the shared Show into the user's own private zone.
            EclipseSyncController.shared.isApplyingRemote = true
            defer { EclipseSyncController.shared.isApplyingRemote = false }
            for modification in changes.modifications {
                let record = modification.record
                switch record.recordType {
                case CloudKitSchema.RecordType.show:
                    if let album = CloudKitRecordMapper.album(from: record) {
                        LocalAlbumStore.shared.applySynced(
                            album,
                            modifiedAt: CloudKitRecordMapper.showModifiedAt(from: record)
                        )
                    }
                case CloudKitSchema.RecordType.mediaItem:
                    if let capture = CloudKitRecordMapper.capture(from: record) {
                        CaptureStore.shared.applyRemote(capture)
                    }
                case CloudKitSchema.RecordType.pdfDoc:
                    if let doc = CloudKitRecordMapper.savedPDF(from: record) {
                        PDFStore.shared.applyRemote(
                            doc,
                            assetURL: CloudKitRecordMapper.pdfAssetURL(from: record)
                        )
                    }
                default:
                    break
                }
            }
            for deletion in changes.deletions {
                EclipseSyncController.shared.applyRemoteDeletion(
                    recordName: deletion.recordID.recordName
                )
            }
        default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext,
        syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        // Participants typically do not push through this host in Phase 1.
        nil
    }
}
