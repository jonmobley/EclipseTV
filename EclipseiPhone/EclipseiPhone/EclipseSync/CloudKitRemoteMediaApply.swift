//
//  CloudKitRemoteMediaApply.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Applies a fetched MediaItem into local stores and keeps the asset bytes that
/// already crossed the network, when eviction policy allows.
///
/// Private and shared `CKSyncEngine` hosts both call this so a Share participant
/// does not discard bytes and pay for a second download on tap.
enum CloudKitRemoteMediaApply {

    /// Writes capture / import metadata, preferences, and optionally the asset.
    @MainActor
    static func apply(
        _ record: CKRecord,
        hasPendingLocalPrefs: Bool,
        wasEvictedByUser: Bool
    ) {
        if CloudKitRecordMapper.isImportedMedia(record),
           let imported = CloudKitRecordMapper.importedMedia(from: record) {
            ImportedMediaStore.shared.applyRemote(imported)
            CloudKitRecordMapper.applyRemoteMediaPrefs(
                from: record,
                libraryId: imported.libraryId,
                hasPendingLocalEdits: hasPendingLocalPrefs
            )
            TVLibraryStore.shared.refreshMergedImports()
            adoptFetchedAsset(
                from: record,
                libraryId: imported.libraryId,
                mode: imported.orientation.libraryMode,
                provenance: .imported,
                wasEvictedByUser: wasEvictedByUser
            ) {
                ImportedMediaStore.shared.setSyncState(id: imported.cloudId, .synced)
                TVLibraryStore.shared.refreshMergedImports()
            }
            return
        }
        if let capture = CloudKitRecordMapper.capture(from: record) {
            CaptureStore.shared.applyRemote(capture)
            CloudKitRecordMapper.applyRemoteMediaPrefs(
                from: record,
                libraryId: capture.libraryFileName,
                hasPendingLocalEdits: hasPendingLocalPrefs
            )
            TVLibraryStore.shared.refreshMergedCaptures()
            adoptFetchedAsset(
                from: record,
                libraryId: capture.libraryFileName,
                mode: capture.orientation.libraryMode,
                provenance: .captured,
                wasEvictedByUser: wasEvictedByUser
            ) {
                CaptureStore.shared.setSyncState(id: capture.id, .synced)
                TVLibraryStore.shared.refreshMergedCaptures()
            }
        }
    }

    /// Keeps the asset bytes that arrived with `record`, when policy allows.
    ///
    /// The copy runs off the main thread because a full-resolution video can be
    /// hundreds of megabytes. The `CKAsset` is held across it so CloudKit's staged
    /// file — which the system purges on its own schedule — outlives the copy.
    @MainActor
    private static func adoptFetchedAsset(
        from record: CKRecord,
        libraryId: String,
        mode: EclipseShareProtocol.LibraryMode,
        provenance: MediaProvenance,
        wasEvictedByUser: Bool,
        onStored: @escaping () -> Void
    ) {
        let asset = record[CloudKitSchema.MediaKey.asset] as? CKAsset
        guard let assetURL = CloudKitAssetAdoptionPolicy.adoptableURL(
            asset?.fileURL,
            hasLocalBytes: LocalMediaStore.shared.hasMedia(forId: libraryId, mode: mode),
            wasEvictedByUser: wasEvictedByUser
        ) else { return }
        LocalMediaStore.shared.store(
            fileURL: assetURL,
            forId: libraryId,
            mode: mode,
            provenance: provenance
        ) { stored in
            withExtendedLifetime(asset) {
                guard stored else { return }
                onStored()
            }
        }
    }
}
