//
//  AudioLibraryViewController+Presentation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension AudioLibraryViewController {

    /// Navigation wrapper presented as a sheet to choose something to play.
    ///
    /// Matches the Now Playing sheet: medium/large detents in portrait, and a
    /// mini-player-width card when height is compact.
    static func makePickerNavigation(
        onAddMusic: (() -> Void)?
    ) -> UINavigationController {
        let library = AudioLibraryViewController(embedded: false)
        library.onAddMusic = onAddMusic
        let nav = UINavigationController(rootViewController: library)
        nav.preferredContentSize = CGSize(
            width: AudioMiniPlayerView.compactWidth,
            height: 520
        )
        if let sheet = nav.sheetPresentationController {
            sheet.detents = [.medium(), .large()]
            sheet.selectedDetentIdentifier = .medium
            sheet.prefersGrabberVisible = true
            sheet.prefersEdgeAttachedInCompactHeight = true
            sheet.widthFollowsPreferredContentSizeWhenEdgeAttached = true
            sheet.preferredCornerRadius = AudioMiniPlayerView.compactCornerRadius
        }
        return nav
    }
}
