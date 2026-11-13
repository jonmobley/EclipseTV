//
//  UnavailableMediaReason.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Why a library item can't play, so its menu talks about the right thing.
///
/// `LibraryItemDTO.isAvailable == false` covers two unrelated cases: an iCloud item
/// whose file hasn't reached this phone yet, and a file the Apple TV no longer has.
/// Treating both as the second showed "no longer on the Apple TV" and "Re-send from
/// Photos" on phones that never paired a TV.
enum UnavailableMediaReason: Equatable {
    /// Synced through iCloud; the file hasn't downloaded to this phone yet.
    case waitingForICloud
    /// Listed by the Apple TV's library, which no longer has the file.
    case missingOnAppleTV

    /// The reason `item` can't play, or nil when it can.
    @MainActor
    static func of(_ item: LibraryItemDTO) -> UnavailableMediaReason? {
        of(item, isSyncedThroughICloud: { id in
            ImportedMediaStore.shared.record(id: id) != nil
                || CaptureStore.shared.record(id: id) != nil
        })
    }

    /// Testable core: `isSyncedThroughICloud` says whether an id is an iCloud row.
    static func of(
        _ item: LibraryItemDTO,
        isSyncedThroughICloud: (String) -> Bool
    ) -> UnavailableMediaReason? {
        guard item.isAvailable == false else { return nil }
        return isSyncedThroughICloud(item.id) ? .waitingForICloud : .missingOnAppleTV
    }

    static let iCloudTitle = "Downloading from iCloud…"
    static let iCloudMessage = "This item is still downloading from iCloud. It can go live once it's on this device."
}
