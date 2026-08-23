//
//  LiveHeaderView+SlideshowBrowse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Slideshow Swipe & Ribbon Toggle

extension LiveHeaderView {

    /// Installs left/right swipes that call `onSlideshowSwipe` (±1).
    func installSlideshowBrowseGestures() {
        let left = UISwipeGestureRecognizer(
            target: self, action: #selector(slideshowSwipeLeft)
        )
        left.direction = .left
        addGestureRecognizer(left)

        let right = UISwipeGestureRecognizer(
            target: self, action: #selector(slideshowSwipeRight)
        )
        right.direction = .right
        addGestureRecognizer(right)
    }

    /// Shows or hides the hero control that toggles the live slide ribbon.
    ///
    /// - Parameters:
    ///   - visible: When true, the slideshow owns live output for this Show.
    ///   - isOn: Current `showRibbonWhenLive` preference.
    func setSlideshowRibbonToggleVisible(_ visible: Bool, isOn: Bool) {
        guard visible else {
            slideshowRibbonButton?.removeFromSuperview()
            slideshowRibbonButton = nil
            applyInteractionForPresentation()
            return
        }
        if slideshowRibbonButton == nil {
            installSlideshowRibbonButton()
        }
        applySlideshowRibbonButtonAppearance(isOn: isOn)
        bringSlideshowRibbonChromeToFront()
        applyInteractionForPresentation()
    }

    // MARK: - Private

    private func installSlideshowRibbonButton() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.onToggleSlideshowRibbon?()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
        slideshowRibbonButton = button
    }

    private func applySlideshowRibbonButtonAppearance(isOn: Bool) {
        guard let button = slideshowRibbonButton else { return }
        let name = isOn ? "rectangle.split.1x2.fill" : "rectangle.split.1x2"
        var config = button.configuration ?? .plain()
        config.image = UIImage(
            systemName: name,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        )
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        button.configuration = config
        button.accessibilityLabel = "Slide Ribbon"
        button.accessibilityValue = isOn ? "On" : "Off"
        button.accessibilityHint = isOn
            ? "Hides the slide ribbon under the preview"
            : "Shows the slide ribbon under the preview"
    }

    private func bringSlideshowRibbonChromeToFront() {
        if let button = slideshowRibbonButton {
            bringSubviewToFront(button)
        }
    }

    @objc private func slideshowSwipeLeft() {
        guard allowsSlideshowBrowse else { return }
        onSlideshowSwipe?(1)
    }

    @objc private func slideshowSwipeRight() {
        guard allowsSlideshowBrowse else { return }
        onSlideshowSwipe?(-1)
    }
}
