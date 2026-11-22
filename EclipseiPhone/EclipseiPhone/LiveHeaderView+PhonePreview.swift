//
//  LiveHeaderView+PhonePreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Phone Preview Chrome

extension LiveHeaderView {

    /// Marks the hero as a phone-only preview: PREVIEW badge plus a return button.
    ///
    /// Re-applied after every hero refresh, after `setBlackoutHold`, because content
    /// updates rewrite the badge (Practice hides it) and the preview must always say
    /// that the room is not seeing this.
    /// - Parameter returnTitle: "Back to Live" or "Back to Blackout".
    func setPhonePreview(_ active: Bool, returnTitle: String) {
        if isPhonePreview != active {
            isPhonePreview = active
            applyOutputLockChrome()
        }
        guard active else {
            phonePreviewReturnButton?.removeFromSuperview()
            phonePreviewReturnButton = nil
            return
        }
        liveBadge.isHidden = false
        let button = phonePreviewReturnButton ?? installPhonePreviewReturnButton()
        var config = button.configuration
        config?.title = returnTitle
        button.configuration = config
        button.accessibilityLabel = returnTitle
        button.alpha = max(0, 1 - collapseProgress * 2)
        bringSubviewToFront(liveBadge)
        bringSubviewToFront(button)
        let base = accessibilityLabel ?? ""
        if !base.hasPrefix("Preview") {
            accessibilityLabel = "Preview on this phone only, not on the TV. \(base)"
        }
    }

    private func installPhonePreviewReturnButton() -> UIButton {
        var config = UIButton.Configuration.plain()
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(top: 4, leading: 10, bottom: 4, trailing: 10)
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var out = incoming
            out.font = UIFontMetrics(forTextStyle: .caption1)
                .scaledFont(for: .systemFont(ofSize: 13, weight: .semibold))
            return out
        }
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.6)
        button.layer.cornerRadius = 6
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            Haptics.impactLight()
            self?.onReturnFromPhonePreview?()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.leadingAnchor.constraint(equalTo: liveBadge.trailingAnchor, constant: 8),
            button.centerYAnchor.constraint(equalTo: liveBadge.centerYAnchor),
            button.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -56),
        ])
        phonePreviewReturnButton = button
        // The hero only takes touches when something on it wants them.
        applyInteractionForPresentation()
        return button
    }
}
