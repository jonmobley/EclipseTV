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
    ///   - mode: Current framing; the icon reflects this mode.
    func setScreenFitToggleVisible(_ visible: Bool, mode: MediaFitMode) {
        guard visible else {
            screenFitButton?.removeFromSuperview()
            screenFitButton = nil
            applyInteractionForPresentation()
            return
        }
        if screenFitButton == nil {
            installScreenFitButton()
        }
        applyScreenFitButtonAppearance(mode: mode)
        bringScreenFitChromeToFront()
        applyInteractionForPresentation()
    }

    // MARK: - Private

    private func installScreenFitButton() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
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
        var config = button.configuration ?? .plain()
        config.image = UIImage(
            systemName: mode.iconName,
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold
            )
        )
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
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
