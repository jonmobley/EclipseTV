//
//  TVGridMetrics.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics

/// Landscape / Vertical tile math for the EclipseTV library grid.
///
/// Apple TV stays landscape; Vertical only changes tile aspect (9:16) and column
/// density. Fullscreen letterboxes — it does not rotate like AirPlay Vertical.
enum TVGridMetrics {

    /// Minimum tile side so a zero-width early layout cannot produce a non-positive size.
    static let minimumTileSide: CGFloat = 80

    /// Cell height ÷ width: 16:9 in Landscape, 9:16 in Vertical.
    static func cellHeightOverWidth(
        for mode: EclipseShareProtocol.LibraryMode
    ) -> CGFloat {
        switch mode {
        case .landscape: return 9.0 / 16.0
        case .vertical: return 16.0 / 9.0
        }
    }

    /// Columns for the TV library grid (Vertical packs denser so portrait tiles stay usable).
    static func columnCount(for mode: EclipseShareProtocol.LibraryMode) -> Int {
        switch mode {
        case .landscape: return 3
        case .vertical: return 5
        }
    }

    /// Decode / Multipeer thumbnail target for the active library mode.
    static func thumbnailTargetSize(
        for mode: EclipseShareProtocol.LibraryMode
    ) -> CGSize {
        switch mode {
        case .landscape: return CGSize(width: 480, height: 270)
        case .vertical: return CGSize(width: 270, height: 480)
        }
    }

    /// Fallback `itemSize` when the collection layout has not prepared yet.
    static func fallbackItemSize(
        for mode: EclipseShareProtocol.LibraryMode
    ) -> CGSize {
        switch mode {
        case .landscape: return CGSize(width: 300, height: 169)
        case .vertical: return CGSize(width: 169, height: 300)
        }
    }

    /// Focus / cache preload size for video thumbs.
    static func preloadItemSize(
        for mode: EclipseShareProtocol.LibraryMode
    ) -> CGSize {
        switch mode {
        case .landscape: return CGSize(width: 400, height: 225)
        case .vertical: return CGSize(width: 225, height: 400)
        }
    }

    /// Flow-layout item size for a given collection width and library mode.
    static func itemSize(
        collectionWidth: CGFloat,
        mode: EclipseShareProtocol.LibraryMode,
        sideInset: CGFloat = 120,
        spacing: CGFloat = 80
    ) -> CGSize {
        let columns = CGFloat(columnCount(for: mode))
        let available = collectionWidth - (sideInset * 2) - (spacing * (columns - 1))
        let width = max(floor(available / columns), minimumTileSide)
        let height = max(
            floor(width * cellHeightOverWidth(for: mode)),
            minimumTileSide
        )
        return CGSize(width: width, height: height)
    }
}
