//
//  CloudKitSyncEngine+AccountReset.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Account change reset

extension CloudKitSyncEngine {

    /// Discards everything that describes the *previous* iCloud account.
    ///
    /// `CKSyncEngine.State.Serialization` holds server change tokens, and the share
    /// roots, change tags, and shared-zone map all name records in an account we can
    /// no longer reach. Reusing them after a switch makes the new engine fetch
    /// against tokens the server never issued.
    ///
    /// Local content is deliberately untouched — it is the user's, and the new
    /// account simply has none of it yet, so everything is marked for re-upload.
    /// Show LWW clocks are also kept: they describe when *this device* last edited a
    /// Show, which stays true across accounts, and clearing them would make local
    /// edits lose every future merge.
    func resetForAccountChange() {
        engine = nil
        UserDefaults.standard.removeObject(forKey: stateKey)
        sharedEngineHost.reset()
        lastKnownRecords.removeAll()
        sharedZones.removeAll()
        pendingDeletes.removeAll()
        shareRoots.removeAll()
        quotaHeldRecordIDs.removeAll()
        markLocalContentForReupload()
        logger.info("Cleared CloudKit state for account change")
    }

    /// Forgets every upload acknowledgement so the new account receives the library.
    ///
    /// Media preference dirt is dropped rather than re-flagged: `markAllNeedsUpload`
    /// re-queues every row that still has local bytes, and those saves carry the
    /// preferences with them. Re-flagging would also queue `.remoteOnly` rows, whose
    /// bytes only ever existed in the old account, so their saves are skipped for a
    /// missing file and their dirty flag would never clear.
    private func markLocalContentForReupload() {
        showDirty.markAllDirty(LocalAlbumStore.shared.albums.map(\.id))
        mediaDirty.removeAll()
        CaptureStore.shared.markAllNeedsUpload()
        ImportedMediaStore.shared.markAllNeedsUpload()
        PDFStore.shared.markAllNeedsUpload()
        WebPageStore.shared.markAllNeedsUpload()
        SlideshowStore.shared.markAllNeedsUpload()
        CountdownStore.shared.markAllNeedsUpload()
        LivePollStore.shared.markAllNeedsUpload()
        CameraFrameStore.shared.markAllNeedsUpload()
        CameraAlternateStillStore.shared.markAllNeedsUpload()
    }
}
