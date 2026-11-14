//
//  LiveHeaderView+ScreenFit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Screen Fit Toggle

extension LiveHeaderView {

    /// Shows or hides the circular Fit / Fill control on the hero.
    ///
    /// - Parameters:
    ///   - visible: Still or slideshow owns live output (not video / overlays).
    ///   - mode: Current framing; the button shows this mode's name.
    func setScreenFitToggleVisible(_ visible: Bool, mode: MediaFitMode) {
        guard visible else {
            screenFitButton?.removeFromSuperview()
            screenFitButton = nil
            layoutSlideshowCountdownRing()
            applyInteractionForPresentation()
            return
        }
        if screenFitButton == nil {
            installScreenFitButton()
        }
        applyScreenFitButtonAppearance(mode: mode)
        bringScreenFitChromeToFront()
        layoutSlideshowCountdownRing()
        applyInteractionForPresentation()
    }

    // MARK: - Private

    private func installScreenFitButton() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = MinimumHitTargetButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.65)
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.onToggleScreenFit?()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        screenFitButton = button
    }

    private func applyScreenFitButtonAppearance(mode: MediaFitMode) {
        guard let button = screenFitButton else { return }
        // The word, not an icon: no symbol read clearly as "Fit" vs "Fill" at this size.
        var config = button.configuration ?? .plain()
        config.image = nil
        var title = AttributedString(mode.rawValue)
        title.font = UIFont.systemFont(ofSize: 13, weight: .semibold)
        config.attributedTitle = title
        config.titleLineBreakMode = .byClipping
        config.baseForegroundColor = .white
        config.contentInsets = .zero
        button.configuration = config
        button.accessibilityLabel = "Screen Fit"
        button.accessibilityValue = mode.rawValue
        button.accessibilityHint = mode == .fill
            ? "Shows the whole image with letterboxing"
            : "Fills the screen and crops overflowing edges"
    }

    private func bringScreenFitChromeToFront() {
        if let button = screenFitButton {
            bringSubviewToFront(button)
        }
    }
}
