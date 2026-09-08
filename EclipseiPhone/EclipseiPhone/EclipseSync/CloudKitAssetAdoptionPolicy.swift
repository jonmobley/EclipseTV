//
//  CloudKitAssetAdoptionPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Whether to keep the asset bytes that arrived with a fetched MediaItem.
///
/// `CKSyncEngine` fetches records with their assets and offers no field-level
/// `desiredKeys` equivalent — `nextFetchChangesOptions` narrows by zone only, and
/// splitting assets into an excluded zone is not possible because a `CKShare` root
/// and its children must share one zone. So the bytes have already crossed the
/// network by the time a record reaches us, and the staging copy is transient:
/// CloudKit purges it, so anything not copied out now costs a second full download.
///
/// Discarding them was therefore pure waste. Keeping them also means the file is
/// ready the instant the user goes live, rather than behind a progress spinner.
enum CloudKitAssetAdoptionPolicy {

    /// Keeps `assetURL` only when it is present, the file is not already on disk,
    /// and the user has not deliberately removed their local copy.
    static func adoptableURL(
        _ assetURL: URL?,
        hasLocalBytes: Bool,
        wasEvictedByUser: Bool
    ) -> URL? {
        guard let assetURL, !hasLocalBytes, !wasEvictedByUser else { return nil }
        return assetURL
    }
}
