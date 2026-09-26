//
//  LegacyMediaBackfill.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Registers pre-Sync imported files with `ImportedMediaStore` so CloudKit can ship them.
///
/// Photos imports that landed before Eclipse Sync existed (legacy Multipeer-only sends,
/// hand transfers, older orphan-recovery passes) live in `LocalMediaStore` under
/// `.imported` but were never given an `ImportedMediaRecord`. `CKSyncEngine` therefore
/// has nothing to upload, and every other device sees the item as either "Unavailable"
/// (via the TV manifest) or missing entirely.
///
/// Once a row exists, `scheduleMediaSave` runs on the current backend and the normal
/// `.pendingUpload` → asset upload → `.synced` path picks it up. Other devices then
/// receive the record via `CloudKitRemoteMediaApply` and adopt the bytes on first fetch.
///
/// Idempotent per id — `ImportedMediaStore.register` short-circuits when a row already
/// exists, so re-running does nothing.
@MainActor
enum LegacyMediaBackfill {

    private static let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "LegacyMediaBackfill"
    )

    /// Walks both library buckets and enrolls unregistered imported files.
    static func run() {
        var registered = 0
        for mode in EclipseShareProtocol.LibraryMode.allCases {
            registered += backfill(mode: mode)
        }
        guard registered > 0 else { return }
        logger.info(
            "Backfilled \(registered, privacy: .public) legacy imports into ImportedMediaStore"
        )
    }

    /// Registers every `.imported` file in `mode` that has no capture or import record.
    ///
    /// Captures are excluded on purpose: `CaptureStore` owns them, and mixing an
    /// `.imported` registration for a capture would fork ownership. `duration` starts at 0
    /// because we don't have it here; `TVLibraryStore.fillMissingVideoDurations` fills
    /// videos lazily as thumbnails warm.
    private static func backfill(mode: EclipseShareProtocol.LibraryMode) -> Int {
        let orientation: ExternalOutputOrientation =
            mode == .landscape ? .landscape : .portrait
        let ids = LocalMediaStore.shared.storedIds(for: mode, provenance: .imported)
        var count = 0
        for id in ids {
            if ImportedMediaStore.shared.record(id: id) != nil { continue }
            if CaptureStore.shared.contains(id: id) { continue }
            _ = ImportedMediaStore.shared.register(
                libraryId: id,
                isVideo: isVideoFilename(id),
                duration: 0,
                orientation: orientation,
                showId: nil
            )
            count += 1
        }
        return count
    }

    private static func isVideoFilename(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return ["mp4", "mov", "m4v", "avi", "mkv"].contains(ext)
    }
}
