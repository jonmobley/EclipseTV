//
//  LiveHeaderView+Expand.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The fullscreen surface an expanded live hero stands in for.
enum HeroExpandTarget: Equatable {
    /// Fullscreen Preview of the phone-local library media in the hero.
    case fullscreenPreview
    /// The phone browser / PDF reader driving the live page.
    case overlayController
    /// The phone camera controller.
    case cameraController
    /// Live Poll host CONTROLS.
    case hostController

    /// Whether the top-trailing control advertises this target.
    ///
    /// CONTROLS is a half sheet, so an expand glyph on the Live Poll hero would
    /// promise a fullscreen surface the tap does not open. That hero keeps the
    /// body tap on its own.
    var showsExpandControl: Bool { self != .hostController }

    /// Spoken name for the control.
    var controlAccessibilityLabel: String {
        switch self {
        case .fullscreenPreview, .overlayController:
            return "Full Screen"
        case .cameraController:
            return "Camera Controls"
        case .hostController:
            return "Controls"
        }
    }
}

// MARK: - Hero Expand Control

extension LiveHeaderView {

    /// What expanding this hero opens, for both the body tap and the control.
    ///
    /// One resolver for the two, or a visible button would promise something the
    /// tap does not do. The order is precedence: a hero owns exactly one live
    /// kind, and `resetTapAffordances()` clears the rest on every content change.
    var heroExpandTarget: HeroExpandTarget? {
        if allowsHostControllerTap { return .hostController }
        if allowsCameraControllerTap { return .cameraController }
        if allowsOverlayControllerTap { return .overlayController }
        if allowsFullscreenTap || allowsLibraryVideoFullscreen {
            return .fullscreenPreview
        }
        return nil
    }

    /// Opens the hero's fullscreen surface. False when it stands for nothing.
    @discardableResult
    func requestExpandedPresentation() -> Bool {
        guard let target = heroExpandTarget else { return false }
        Haptics.impactLight()
        switch target {
        case .hostController:
            onRequestHostController?()
        case .cameraController:
            onRequestCameraController?()
        case .overlayController:
            onRequestOverlayController?()
        case .fullscreenPreview:
            onRequestFullscreen?()
        }
        return true
    }

    /// Installs or removes the top-trailing expand control for the current hero.
    ///
    /// Website, PDF, and Camera heroes used to offer their controller through a
    /// tap on the hero and nothing else. Once the user closed the browser, reader,
    /// or viewfinder there was no visible way back to it — the preview looked like
    /// a picture of what was live rather than a way into it.
    ///
    /// Driven from `refreshLiveHeader` alongside Screen Fit and Flip Camera so the
    /// subview is added outside a layout pass. The slide-ribbon toggle takes the
    /// same corner, and runs first there, but a live slideshow and a live
    /// website / PDF / camera are mutually exclusive.
    func syncExpandControl() {
        guard let target = heroExpandTarget, target.showsExpandControl else {
            heroExpandButton?.removeFromSuperview()
            heroExpandButton = nil
            applyInteractionForPresentation()
            return
        }
        if heroExpandButton == nil {
            installExpandControl()
        }
        heroExpandButton?.accessibilityLabel = target.controlAccessibilityLabel
        bringExpandControlToFront()
        applyInteractionForPresentation()
    }

    /// Keeps the control above content hosts and the crossfade snapshot.
    func bringExpandControlToFront() {
        guard let button = heroExpandButton else { return }
        bringSubviewToFront(button)
    }

    // MARK: - Private

    private func installExpandControl() {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "arrow.up.left.and.arrow.down.right",
            withConfiguration: UIImage.SymbolConfiguration(
                pointSize: 14, weight: .semibold
            )
        )
        config.baseForegroundColor = .white
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 8, bottom: 8, trailing: 8
        )
        let button = UIButton(configuration: config)
        button.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        button.layer.cornerRadius = 8
        button.clipsToBounds = true
        button.translatesAutoresizingMaskIntoConstraints = false
        button.addAction(UIAction { [weak self] _ in
            self?.requestExpandedPresentation()
        }, for: .touchUpInside)
        addSubview(button)
        NSLayoutConstraint.activate([
            button.trailingAnchor.constraint(
                equalTo: trailingAnchor, constant: -10
            ),
            button.topAnchor.constraint(equalTo: topAnchor, constant: 10)
        ])
        heroExpandButton = button
    }
}
