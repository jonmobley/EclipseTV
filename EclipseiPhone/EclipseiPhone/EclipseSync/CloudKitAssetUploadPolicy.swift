//
//  CloudKitAssetUploadPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Decides whether a MediaItem save carries its file or only its metadata.
///
/// Already-`.synced` media is re-enqueued on bootstrap and on every foreground so
/// local Fit / framing / loop / mute edits reach other devices. Attaching a fresh
/// `CKAsset` to those saves re-uploaded the whole photo or video each time. A
/// CloudKit save is a partial update, so leaving the asset field unset preserves
/// the copy already on the server.
enum CloudKitAssetUploadPolicy {

    /// The asset URL when CloudKit still needs the bytes, otherwise nil.
    ///
    /// Only `.pendingUpload` warrants the file: it is the state for media the server
    /// has never accepted, including anything re-queued after zone loss or an iCloud
    /// account switch. Every other state means the asset is already stored.
    static func assetURL(_ url: URL, state: CaptureSyncState) -> URL? {
        state == .pendingUpload ? url : nil
    }
}
