//
//  VideoPreviewTitleLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CoreGraphics

/// Placement and visibility rules for the title floating over a video Preview.
enum VideoPreviewTitleLayout {

    /// How far down the picture the title sits — the upper third.
    static let heightFraction: CGFloat = 1.0 / 3.0

    /// Clearance under the safe area so the title never lands on the Close row.
    static let minimumTopInset: CGFloat = 64

    /// Centre Y for the title, a third of the way down the picture.
    ///
    /// Measured against the picture rather than the player so a letterboxed clip puts
    /// its title over the image instead of into the black bar above it.
    ///
    /// - Parameters:
    ///   - videoBounds: `AVPlayerViewController.videoBounds` in `playerBounds`' space.
    ///     Empty until the player has laid the picture out, hence `presentationSize`.
    ///   - presentationSize: Track size of the item, `.zero` until the item loads.
    ///   - playerBounds: Player view bounds; the picture when neither size is known yet.
    ///   - minimumCenterY: Floor from the top of `playerBounds`.
    /// - Returns: Offset from the top of `playerBounds`.
    static func titleCenterY(
        videoBounds: CGRect,
        presentationSize: CGSize,
        playerBounds: CGRect,
        minimumCenterY: CGFloat
    ) -> CGFloat {
        let picture = videoBounds.height > 1
            ? videoBounds
            : pictureRect(presentationSize: presentationSize, playerBounds: playerBounds)
        return max(picture.minY + picture.height * heightFraction, minimumCenterY)
    }

    /// Where a clip of `presentationSize` lands when shown aspect-fit in `playerBounds`.
    ///
    /// Falls back to the full player for an unknown size, which is also what an
    /// aspect-filling clip occupies.
    static func pictureRect(presentationSize: CGSize, playerBounds: CGRect) -> CGRect {
        guard presentationSize.width > 0, presentationSize.height > 0,
              playerBounds.width > 0, playerBounds.height > 0 else { return playerBounds }
        let scale = min(
            playerBounds.width / presentationSize.width,
            playerBounds.height / presentationSize.height
        )
        let size = CGSize(
            width: presentationSize.width * scale,
            height: presentationSize.height * scale
        )
        return CGRect(
            x: playerBounds.midX - size.width / 2,
            y: playerBounds.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// Shows the title while the picture is moving.
    ///
    /// Pausing raises the system controls, which is chrome enough; buffering counts as
    /// playing so a stall does not blink the title away.
    static func isVisible(hasTitle: Bool, isPlaying: Bool) -> Bool {
        hasTitle && isPlaying
    }
}
