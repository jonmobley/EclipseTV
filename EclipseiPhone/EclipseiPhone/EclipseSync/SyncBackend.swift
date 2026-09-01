//
//  SyncBackend.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Transport-agnostic surface for multi-device Show / capture sync.
///
/// CloudKit is the shipping implementation. Call sites depend on this protocol so a
/// future Supabase + R2 backend can replace the transport without UI rewrites.
@MainActor
protocol SyncBackend: AnyObject {
    /// Whether the user can sync (signed into iCloud / authenticated).
    var isAccountAvailable: Bool { get }

    /// Human-readable reason sync is paused, if any (quota, no account, etc.).
    var pauseReason: SyncPauseReason? { get }

    /// Starts engines / observers. Safe to call repeatedly.
    func start()

    /// Re-enqueues pending uploads after foregrounding or a transient failure.
    func retryPendingWork()

    /// Schedules a Show metadata upload (name, membership, cover, orientation).
    func scheduleShowSave(id: UUID)

    /// Schedules deletion of a Show record (does not delete media blobs).
    func scheduleShowDelete(id: UUID)

    /// Schedules a capture metadata (+ asset when local) upload.
    func scheduleCaptureSave(id: String)

    /// Schedules deletion of a capture record and its cloud asset.
    func scheduleCaptureDelete(id: String)

    /// Schedules an imported-media metadata (+ asset) upload.
    func scheduleMediaSave(cloudId: String)

    /// Schedules deletion of an imported-media record and its cloud asset.
    func scheduleMediaDelete(cloudId: String)

    /// Schedules a saved-PDF upload (title + the `.pdf` file itself).
    func schedulePDFSave(id: UUID)

    /// Schedules deletion of a PDF record and its cloud file.
    func schedulePDFDelete(id: UUID)

    /// Schedules a website metadata upload.
    func scheduleWebPageSave(id: UUID)

    /// Schedules deletion of a website record.
    func scheduleWebPageDelete(id: UUID)

    /// Schedules a slideshow metadata upload.
    func scheduleSlideshowSave(id: UUID)

    /// Schedules deletion of a slideshow record.
    func scheduleSlideshowDelete(id: UUID)

    /// Schedules a countdown metadata upload.
    func scheduleCountdownSave(id: UUID)

    /// Schedules deletion of a countdown record.
    func scheduleCountdownDelete(id: UUID)

    /// Schedules a Live Poll card metadata upload.
    func scheduleLivePollSave(id: UUID)

    /// Schedules deletion of a Live Poll card record.
    func scheduleLivePollDelete(id: UUID)

    /// Schedules the account-global Background custom image upload (or clear).
    func scheduleBackgroundSave()

    /// Schedules deletion of the custom Background (restore bundled).
    func scheduleBackgroundDelete()

    /// Schedules the account-global Screensaver custom media upload (or clear).
    func scheduleScreensaverSave()

    /// Schedules deletion of the custom Screensaver (restore bundled).
    func scheduleScreensaverDelete()

    /// Schedules a camera frame PNG upload.
    func scheduleCameraFrameSave(id: UUID)

    /// Schedules deletion of a camera frame.
    func scheduleCameraFrameDelete(id: UUID)

    /// Schedules per-orientation camera ribbon settings upload.
    func scheduleCameraSettingsSave(orientation: ExternalOutputOrientation)

    /// Schedules a camera cutaway still upload.
    func scheduleCutawaySave(id: UUID)

    /// Schedules deletion of a camera cutaway still.
    func scheduleCutawayDelete(id: UUID)

    /// Downloads the full-resolution asset for `id` when it is not on disk.
    func downloadAsset(
        id: String,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    )

    /// Removes the local download for `id` without deleting the cloud record.
    func removeLocalDownload(id: String)

    /// Presents system sharing UI for a Show (CloudKit `CKShare`).
    func presentShareUI(forShowId id: UUID, from presenter: AnyObject)
}

/// Why EclipseSync is not actively uploading / downloading.
enum SyncPauseReason: Equatable {
    case noAccount
    case quotaExceeded
    case temporarilyUnavailable(String)

    /// Short copy for banners and alerts.
    var userMessage: String {
        switch self {
        case .noAccount:
            return "Sign in to iCloud in Settings to sync Shows across your devices."
        case .quotaExceeded:
            return "Your iCloud storage is full. Free up space to resume Eclipse Sync."
        case .temporarilyUnavailable(let detail):
            return detail
        }
    }
}

/// Per-item local sync / download state for capture media.
enum CaptureSyncState: String, Codable, Equatable {
    /// Local only; not yet scheduled or acknowledged by the backend.
    case localOnly
    /// Queued for upload.
    case pendingUpload
    /// Metadata (and asset, when applicable) is on the server.
    case synced
    /// Known from the server; full-res file not on this device.
    case remoteOnly
    /// Download of the full-res asset is in flight.
    case downloading
}
