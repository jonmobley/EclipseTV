//
//  MediaSyncPresence.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What a library tile should say about where its full-resolution bytes are.
///
/// `LibraryItemDTO.isAvailable == false` is overloaded: the TV manifest uses it for a
/// file the Apple TV purged, while `CaptureRecord` / `ImportedMediaRecord` use it for a
/// CloudKit item that is `.remoteOnly` on this phone. The two need different tile copy
/// and a different tap — one can only be re-sent from Photos, the other downloads.
enum MediaSyncPresence: Equatable {
    /// Bytes are here (or this is a plain TV item). No badge.
    case local
    /// Queued for iCloud; other devices don't have it yet.
    case pendingUpload
    /// In iCloud but not on this device. Tap downloads.
    case inCloud
    /// Download in flight.
    case downloading
    /// The Apple TV lost its copy; only a re-send from Photos restores it.
    case purgedOnTV

    // MARK: - Resolution

    /// Pure resolution from a record's sync state and the DTO's availability flag.
    ///
    /// - Parameters:
    ///   - syncState: Nil when the item has no CloudKit record.
    ///   - isAvailable: The DTO flag; false is the TV's "purged" signal.
    ///   - isSyncActive: When sync is paused the banner already explains why, so a
    ///     per-tile "waiting to upload" badge on every item would only be noise.
    static func resolve(
        syncState: CaptureSyncState?,
        isAvailable: Bool?,
        isSyncActive: Bool = true
    ) -> MediaSyncPresence {
        switch syncState {
        case .remoteOnly:
            return .inCloud
        case .downloading:
            return .downloading
        case .pendingUpload:
            return isSyncActive ? .pendingUpload : .local
        case .localOnly, .synced, .none:
            return isAvailable == false ? .purgedOnTV : .local
        }
    }

    /// Presence for a grid item, read from the live registries rather than the DTO.
    ///
    /// Merged DTOs keep the availability they had when first merged, so a download
    /// that finished a moment ago would still paint as remote if the tile trusted them.
    @MainActor
    static func resolve(for item: LibraryItemDTO) -> MediaSyncPresence {
        resolve(
            syncState: cloudSyncState(forLibraryId: item.id),
            isAvailable: item.isAvailable,
            isSyncActive: EclipseSyncController.shared.isAccountAvailable
        )
    }

    /// Sync state of the capture or import behind `id`, if either registry knows it.
    @MainActor
    static func cloudSyncState(forLibraryId id: String) -> CaptureSyncState? {
        if let capture = CaptureStore.shared.record(id: id) { return capture.syncState }
        if let imported = ImportedMediaStore.shared.record(id: id) { return imported.syncState }
        return nil
    }

    // MARK: - Tile chrome

    /// Whether the tile's bytes can play right now.
    var isPlayable: Bool { self == .local || self == .pendingUpload }

    /// True when a tap should fetch from iCloud instead of offering a Photos re-send.
    var wantsCloudDownload: Bool { self == .inCloud || self == .downloading }

    /// Bottom-centre pill text, or nil when the tile carries no pill.
    var pillTitle: String? {
        switch self {
        case .local, .pendingUpload: return nil
        case .inCloud: return "In iCloud"
        case .downloading: return "Downloading…"
        case .purgedOnTV: return "Unavailable"
        }
    }

    /// SF Symbol beside the pill text, when one helps.
    var pillSymbolName: String? {
        self == .inCloud ? "icloud.and.arrow.down" : nil
    }

    /// Thumbnail alpha. A purged file is gone; an iCloud copy is one tap away.
    var thumbnailAlpha: CGFloat {
        switch self {
        case .local, .pendingUpload: return 1
        case .inCloud, .downloading: return 0.55
        case .purgedOnTV: return 0.35
        }
    }

    /// VoiceOver suffix, or nil when there is nothing to add.
    var accessibilitySuffix: String? {
        switch self {
        case .local: return nil
        case .pendingUpload: return "waiting to upload"
        case .inCloud: return "in iCloud"
        case .downloading: return "downloading"
        case .purgedOnTV: return "unavailable"
        }
    }
}
