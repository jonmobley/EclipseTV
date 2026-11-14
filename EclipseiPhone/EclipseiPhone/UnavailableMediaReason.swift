//
//  UnavailableMediaReason.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Why a library item can't play, so its tile, tap and menu talk about the right thing.
///
/// `LibraryItemDTO.isAvailable == false` covers unrelated cases: an iCloud item whose
/// file isn't on this phone (waiting for a tap, or downloading now), and a file the
/// Apple TV no longer has. Treating them alike showed "no longer on the Apple TV" on
/// phones that never paired a TV, and "Downloading…" on items nothing was fetching.
enum UnavailableMediaReason: Equatable {
    /// Synced through iCloud; the file isn't on this device. A tap downloads it.
    case inICloud
    /// Synced through iCloud; the file is downloading now.
    case downloading
    /// Listed by the Apple TV's library, which no longer has the file.
    case missingOnAppleTV

    /// The reason `item` can't play, or nil when it can.
    @MainActor
    static func of(_ item: LibraryItemDTO) -> UnavailableMediaReason? {
        guard item.isAvailable == false else { return nil }
        return of(item, iCloudState: { id in
            CaptureStore.shared.record(id: id)?.syncState
                ?? ImportedMediaStore.shared.record(id: id)?.syncState
        })
    }

    /// Testable core: `iCloudState` gives the sync state of an iCloud row, or nil when
    /// `id` isn't one.
    static func of(
        _ item: LibraryItemDTO,
        iCloudState: (String) -> CaptureSyncState?
    ) -> UnavailableMediaReason? {
        guard item.isAvailable == false else { return nil }
        guard let state = iCloudState(item.id) else { return .missingOnAppleTV }
        return state == .downloading ? .downloading : .inICloud
    }

    /// True for both iCloud cases: the file can come down, unlike a TV purge.
    var isICloud: Bool { self != .missingOnAppleTV }

    /// Bottom-centre tile pill.
    var pillTitle: String {
        switch self {
        case .inICloud: return "In iCloud"
        case .downloading: return "Downloading…"
        case .missingOnAppleTV: return "Unavailable"
        }
    }

    static let downloadTitle = "Download from iCloud"
    static let downloadingTitle = "Downloading from iCloud…"
    static let inICloudMessage = "This item is in iCloud but not on this device yet. Download it to go live."
    static let downloadingMessage = "This item is downloading from iCloud. It can go live once it's on this device."
    static let downloadFailedTitle = "Couldn't Download from iCloud"
}
