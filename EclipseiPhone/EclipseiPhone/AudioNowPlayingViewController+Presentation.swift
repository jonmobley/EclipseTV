//
//  AudioNowPlayingViewController+Presentation.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension AudioNowPlayingViewController {

    /// Navigation wrapper presented as a sheet.
    ///
    /// Portrait stays a standard bottom sheet. Landscape compact height stays a
    /// card the width of the mini player instead of going full screen.
    static func makeNavigation(
        onOpenLibrary: (() -> Void)?
    ) -> UINavigationController {
        let nowPlaying = AudioNowPlayingViewController()
        nowPlaying.onOpenLibrary = onOpenLibrary
        let nav = UINavigationController(rootViewController: nowPlaying)
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
