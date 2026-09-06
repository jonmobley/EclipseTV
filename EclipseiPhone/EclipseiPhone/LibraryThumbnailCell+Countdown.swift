//
//  LibraryThumbnailCell+Countdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Countdown Tile

extension LibraryThumbnailCell {

    /// Show-grid Countdown tile: large clock body, name caption, timer type icon.
    ///
    /// Idle tiles pass the saved duration; live tiles pass remaining seconds.
    /// - Parameter isExpired: When live and at zero, the clock turns red (AirPlay match).
    /// - Parameter endHint: Second caption line when an end action is armed.
    func configureCountdown(
        name: String,
        seconds: Int,
        isLive: Bool,
        isLocked: Bool = false,
        isExpired: Bool = false,
        endHint: String? = nil
    ) {
        resetChrome()
        cardView.backgroundColor = UIColor(white: 0.12, alpha: 1)
        imageView.image = nil
        imageView.alpha = 0
        placeholderIcon.isHidden = true

        let clock = CountdownController.displayString(seconds: seconds)
        countdownTimeLabel.text = clock
        countdownTimeLabel.textColor = isExpired ? .systemRed : .white
        countdownTimeLabel.isHidden = false

        captionLabel.text = endHint.map { "\(name)\n\($0)" } ?? name
        captionLabel.numberOfLines = endHint == nil ? 1 : 2
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.isHidden = false
        setTypeIcon(.countdown)
        updateCaptionScrim()
        setLive(isLive, isLocked: isLocked)
        cardView.bringSubviewToFront(countdownTimeLabel)
        cardView.bringSubviewToFront(captionScrimView)
        cardView.bringSubviewToFront(captionLabel)
        if !typeIconOverlay.isHidden {
            cardView.bringSubviewToFront(typeIconOverlay)
        }

        var spoken = "\(name), \(clock), countdown"
        if let endHint {
            spoken += ", \(endHint.lowercased())"
        }
        accessibilityLabel = isLive
            ? (isLocked ? "\(spoken), live, locked" : "\(spoken), live")
            : spoken
        isAccessibilityElement = true
    }

    /// Updates only the clock digits/color during live ticks (keeps ⋯ / live stroke).
    func applyCountdownTime(_ seconds: Int, isExpired: Bool) {
        countdownTimeLabel.text = CountdownController.displayString(seconds: seconds)
        countdownTimeLabel.textColor = isExpired ? .systemRed : .white
        countdownTimeLabel.isHidden = false
    }
}
