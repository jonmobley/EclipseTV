//
//  LiveHeaderView+CameraFlip.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Camera Flip Shortcut

extension LiveHeaderView {

    /// Shows or hides the circular front / back control on the hero.
    ///
    /// Sits in the trailing-bottom slot the Screen Fit control uses, which is free
    /// while the camera owns live output (framing belongs to stills / slideshows).
    ///
    /// - Parameters:
    ///   - visible: The live camera feed owns the hero and the phone has two lenses.
    ///   - isFront: Current lens, reported to VoiceOver.
    ///   - isEnabled: False while recording — the lens cannot change mid-movie.
    func setCameraFlipVisible(
        _ visible: Bool,
        isFront: Bool = false,
        isEnabled: Bool = true
    ) {
        guard visible else {
            if cameraFlipButton != nil {
                cameraFlipButton?.removeFromSuperview()
                cameraFlipButton = nil
                applyInteractionForPresentation()
            }
            return
        }
        if cameraFlipButton == nil {
            installCameraFlipButton()
        }
        applyCameraFlipButtonAppearance(isFront: isFront, isEnabled: isEnabled)
        bringCameraFlipChromeToFront()
        applyInteractionForPresentation()
    }

    /// Keeps the flip control above the embedded camera mirror.
    func bringCameraFlipChromeToFront() {
        guard let button = cameraFlipButton else { return }
        bringSubviewToFront(button)
    }

    // MARK: - Private

    private func installCameraFlipButton() {
        var config = UIButton.Configuration.plain()
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = MinimumHitTargetButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 18
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.onFlipCamera?()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.widthAnchor.constraint(equalToConstant: 36),
            button.heightAnchor.constraint(equalToConstant: 36),
            button.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            button.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -10)
        ])
        cameraFlipButton = button
    }

    private func applyCameraFlipButtonAppearance(isFront: Bool, isEnabled: Bool) {
        guard let button = cameraFlipButton else { return }
        var config = button.configuration ?? .plain()
        config.image = UIImage(
            systemName: "arrow.triangle.2.circlepath.camera",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 13, weight: .semibold
            )
        )
        // Collapse chrome owns `alpha`, so the disabled state dims the glyph
        // instead — fading the button would fight a collapse in progress.
        config.baseForegroundColor = isEnabled
            ? .white
            : UIColor.white.withAlphaComponent(0.45)
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        button.configuration = config
        button.isEnabled = isEnabled
        button.accessibilityLabel = "Flip Camera"
        button.accessibilityValue = isFront ? "Front" : "Back"
        button.accessibilityHint = isEnabled
            ? "Switches between the front and back cameras"
            : "Unavailable while recording"
    }
}
