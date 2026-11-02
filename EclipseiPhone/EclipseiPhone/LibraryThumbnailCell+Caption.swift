//
//  LibraryThumbnailCell+Caption.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Title Strip

extension LibraryThumbnailCell {

    /// Strip height under the picture; grids add it to the tile height.
    static let titleStripHeight: CGFloat = 32

    /// Title colour on the strip (Mac: 90% primary).
    static let titleColor = UIColor.label.withAlphaComponent(0.9)

    /// Strip fill: a step lighter than the card in dark mode, darker in light.
    static let titleStripFill = UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(white: 0.17, alpha: 1)
            : UIColor(white: 0.9, alpha: 1)
    }

    /// One-line title in a strip pinned under the picture (Mac `MediaCardTitleBar`).
    func installTitleStrip() {
        titleStrip.backgroundColor = Self.titleStripFill
        titleStrip.isHidden = true
        titleStrip.isUserInteractionEnabled = false
        titleStrip.translatesAutoresizingMaskIntoConstraints = false
        cardView.addSubview(titleStrip)

        captionLabel.font = .systemFont(ofSize: 12, weight: .medium)
        captionLabel.textColor = Self.titleColor
        captionLabel.textAlignment = .left
        captionLabel.numberOfLines = 1
        captionLabel.lineBreakMode = .byTruncatingTail
        captionLabel.isHidden = true
        captionLabel.translatesAutoresizingMaskIntoConstraints = false
        captionLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        titleStrip.addSubview(captionLabel)

        imageBottomToStrip = imageView.bottomAnchor.constraint(equalTo: titleStrip.topAnchor)
        imageBottomToCard = imageView.bottomAnchor.constraint(equalTo: cardView.bottomAnchor)
        imageBottomToCard.isActive = true
        NSLayoutConstraint.activate([
            titleStrip.leadingAnchor.constraint(equalTo: cardView.leadingAnchor),
            titleStrip.trailingAnchor.constraint(equalTo: cardView.trailingAnchor),
            titleStrip.bottomAnchor.constraint(equalTo: cardView.bottomAnchor),
            titleStrip.heightAnchor.constraint(equalToConstant: Self.titleStripHeight),
            captionLabel.leadingAnchor.constraint(equalTo: titleStrip.leadingAnchor, constant: 10),
            captionLabel.trailingAnchor.constraint(equalTo: titleStrip.trailingAnchor, constant: -10),
            captionLabel.centerYAnchor.constraint(equalTo: titleStrip.centerYAnchor)
        ])
    }

    /// Shows the strip under the picture when there is a title; with none, the
    /// picture fills the card. Add / New Show labels stay centred.
    func updateTitleStrip() {
        let show = showsTitleStrip && !captionLabel.isHidden
            && !(captionLabel.text ?? "").isEmpty
        titleStrip.isHidden = !show
        captionLabel.textAlignment = centersCaption ? .center : .left
        imageBottomToStrip.isActive = false
        imageBottomToCard.isActive = false
        imageBottomToStrip.isActive = show
        imageBottomToCard.isActive = !show
        guard show else { return }
        cardView.bringSubviewToFront(titleStrip)
        if !moreButton.isHidden {
            cardView.bringSubviewToFront(moreButton)
        }
    }

    /// Updates a special-tile caption without resetting ⋯ chrome.
    func applySpecialTitle(
        _ title: String,
        isLive: Bool,
        isLocked: Bool = false,
        typeIcon: ThumbnailTypeIcon? = nil
    ) {
        captionLabel.text = title
        captionLabel.isHidden = false
        var label = isLive
            ? (isLocked ? "\(title), live, locked" : "\(title), live")
            : title
        if let typeIcon {
            let spoken = typeIcon.spokenName
            if title.compare(spoken, options: .caseInsensitive) != .orderedSame {
                label = "\(label), \(spoken)"
            }
        }
        accessibilityLabel = label
        updateTitleStrip()
    }
}
