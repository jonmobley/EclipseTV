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
    /// - Parameter isHeld: Idle tile showing a remainder a tap would resume, marked
    ///   with a pause glyph so it reads as held time rather than a shorter length.
    /// - Parameter endHint: Second caption line when an end action is armed.
    func configureCountdown(
        name: String,
        seconds: Int,
        isLive: Bool,
        isLocked: Bool = false,
        isExpired: Bool = false,
        isHeld: Bool = false,
        endHint: String? = nil
    ) {
        resetChrome()
        cardView.backgroundColor = .mediaPlaceholder
        imageView.image = nil
        imageView.alpha = 0
        placeholderIcon.isHidden = true

        let clock = CountdownController.displayString(seconds: seconds)
        applyCountdownTime(seconds, isExpired: isExpired, isHeld: isHeld)

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

        var spoken = isHeld
            ? "\(name), paused at \(clock), countdown"
            : "\(name), \(clock), countdown"
        if let endHint {
            spoken += ", \(endHint.lowercased())"
        }
        accessibilityLabel = isLive
            ? (isLocked ? "\(spoken), live, locked" : "\(spoken), live")
            : spoken
        isAccessibilityElement = true
    }

    /// Updates only the clock digits/color during live ticks (keeps ⋯ / live stroke).
    func applyCountdownTime(_ seconds: Int, isExpired: Bool, isHeld: Bool = false) {
        let clock = CountdownController.displayString(seconds: seconds)
        if isHeld {
            countdownTimeLabel.attributedText = Self.heldClockText(
                clock, font: countdownTimeLabel.font
            )
        } else {
            countdownTimeLabel.text = clock
        }
        countdownTimeLabel.textColor = isExpired ? .systemRed : .white
        countdownTimeLabel.isHidden = false
    }

    // MARK: - Private

    /// `⏸ 3:00` — the clock with a leading pause glyph sized to the digits.
    ///
    /// The colour is baked into the string rather than left to `textColor` so the
    /// glyph and the digits cannot end up tinted differently.
    private static func heldClockText(_ clock: String, font: UIFont) -> NSAttributedString {
        let text = NSMutableAttributedString()
        let config = UIImage.SymbolConfiguration(font: font, scale: .small)
        if let glyph = UIImage(systemName: "pause.fill", withConfiguration: config) {
            let tinted = glyph.withTintColor(.white, renderingMode: .alwaysOriginal)
            let attachment = NSTextAttachment()
            attachment.image = tinted
            // Attachments sit on the baseline by default, which reads low beside
            // 28pt digits; centre it on the cap height instead.
            attachment.bounds = CGRect(
                x: 0,
                y: (font.capHeight - tinted.size.height) / 2,
                width: tinted.size.width,
                height: tinted.size.height
            )
            text.append(NSAttributedString(attachment: attachment))
            text.append(NSAttributedString(string: " "))
        }
        text.append(NSAttributedString(
            string: clock,
            attributes: [.font: font, .foregroundColor: UIColor.white]
        ))
        return text
    }
}
