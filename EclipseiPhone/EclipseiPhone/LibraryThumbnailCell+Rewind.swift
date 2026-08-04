//
//  LibraryThumbnailCell+Rewind.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Video Resume Rewind

extension LibraryThumbnailCell {

    /// Installs the bottom-leading Rewind pill used after a mid-play leave.
    func installRewindButton() {
        var config = UIButton.Configuration.plain()
        config.title = "Rewind"
        config.image = UIImage(
            systemName: "backward.end.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold)
        )
        config.imagePadding = 4
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 6, leading: 10, bottom: 6, trailing: 10
        )
        config.background.backgroundColor = UIColor.black.withAlphaComponent(0.55)
        config.background.cornerRadius = 14
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 12, weight: .semibold)
            return attrs
        }
        rewindButton.configuration = config
        rewindButton.accessibilityLabel = "Rewind"
        rewindButton.translatesAutoresizingMaskIntoConstraints = false
        rewindButton.isHidden = true
        cardView.addSubview(rewindButton)
        NSLayoutConstraint.activate([
            rewindButton.leadingAnchor.constraint(
                equalTo: cardView.leadingAnchor, constant: 8
            ),
            rewindButton.bottomAnchor.constraint(
                equalTo: cardView.bottomAnchor, constant: -8
            )
        ])
    }

    /// Shows Rewind when a mid-play leave is parked; hides otherwise.
    ///
    /// - Parameter handler: Invoked on tap. Pass nil to hide. Does not go live.
    func setRewindHandler(_ handler: (() -> Void)?) {
        rewindButton.removeTarget(nil, action: nil, for: .allEvents)
        rewindButton.configuration?.baseForegroundColor = .white
        guard let handler else {
            rewindButton.isHidden = true
            return
        }
        rewindButton.isHidden = false
        rewindButton.addAction(UIAction { _ in handler() }, for: .touchUpInside)
        cardView.bringSubviewToFront(rewindButton)
    }

    /// Hides Rewind (called from `resetChrome`).
    func clearRewind() {
        setRewindHandler(nil)
    }
}
