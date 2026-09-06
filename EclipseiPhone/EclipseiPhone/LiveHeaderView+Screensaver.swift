//
//  LiveHeaderView+Screensaver.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - In-App Screensaver Preview

extension LiveHeaderView {

    /// Plays the muted looping Screensaver in the home hero (works without AirPlay).
    ///
    /// A custom still uses the overlay thumbnail only — no video host.
    func showScreensaverPreview() {
        guard let url = ScreensaverStore.videoURL else {
            clearScreensaverPreview()
            setStaticPreviewHidden(false)
            return
        }
        if let existing = screensaverPreview {
            // Same URL already playing — keep it.
            _ = existing
            setStaticPreviewHidden(true)
            bringScreensaverPreviewChromeToFront()
            return
        }
        clearWebPreview(parking: true)
        clearCameraPreview()

        let preview = SeamlessLoopPlayerView(
            url: url, crossfadesAtLoop: ScreensaverStore.shared.crossfadesAtLoop
        )
        preview.translatesAutoresizingMaskIntoConstraints = false
        preview.isUserInteractionEnabled = false
        insertSubview(preview, at: 0)
        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.bottomAnchor.constraint(equalTo: bottomAnchor),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        preview.onReady = { [weak self] in
            guard let self, self.screensaverPreview === preview else { return }
            self.setStaticPreviewHidden(true)
        }
        screensaverPreview = preview
        // Keep the poster up until a decoded frame exists — hiding it first blinks black.
        bringScreensaverPreviewChromeToFront()
        preview.play()
    }

    /// Stops and removes the in-hero Screensaver loop.
    func clearScreensaverPreview() {
        screensaverPreview?.stop()
        screensaverPreview?.removeFromSuperview()
        screensaverPreview = nil
        setStaticPreviewHidden(false)
    }

    /// Keeps LIVE chrome above the embedded Screensaver player.
    private func bringScreensaverPreviewChromeToFront() {
        if let preview = screensaverPreview {
            insertSubview(preview, at: 0)
        }
        // Same stacking as the in-hero web preview (badge / titles / transport).
        bringWebPreviewChromeToFront()
    }
}
