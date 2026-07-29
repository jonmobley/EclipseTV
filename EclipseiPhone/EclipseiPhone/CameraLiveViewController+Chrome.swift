//
//  CameraLiveViewController+Chrome.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Preview / Live Chrome

extension CameraLiveViewController {

    /// Builds centered LIVE status pill (called from `viewDidLoad`).
    func setupPreviewChrome() {
        goLiveButton.isUserInteractionEnabled = false
        goLiveButton.isHidden = true
        view.addSubview(goLiveButton)
        applyLiveBadgeAppearance()
    }

    /// Places Back · centered LIVE · Settings inside the panel.
    func layoutTopChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let inset: CGFloat = 18
        let spacing: CGFloat = 10
        let controlSize = Self.chromeControlSize
        let rowY = panel.minY + inset

        backButton.frame = CGRect(
            x: panel.minX + inset,
            y: rowY,
            width: controlSize,
            height: controlSize
        )

        settingsButton.frame = CGRect(
            x: panel.maxX - inset - controlSize,
            y: rowY,
            width: controlSize,
            height: controlSize
        )

        let goHeight: CGFloat = 44
        goLiveButton.sizeToFit()
        let sideReserve = inset + controlSize + spacing
        let maxGoWidth = max(96, panel.width - sideReserve * 2 - spacing)
        let intrinsic = goLiveButton.intrinsicContentSize.width
        let goWidth = min(max(intrinsic + 8, 72), maxGoWidth)
        let goY = rowY + (controlSize - goHeight) / 2
        goLiveButton.frame = CGRect(
            x: panel.midX - goWidth / 2,
            y: goY,
            width: goWidth,
            height: goHeight
        )

        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(goLiveButton)
        view.bringSubviewToFront(settingsButton)
    }

    /// Builds shutter track + thumb + Flip + camera-roll.
    func setupCaptureMocks() {
        shutterTrackView.translatesAutoresizingMaskIntoConstraints = true
        view.addSubview(shutterTrackView)
        shutterHintView.translatesAutoresizingMaskIntoConstraints = true
        shutterTrackView.addSubview(shutterHintView)

        shutterButton.translatesAutoresizingMaskIntoConstraints = true
        shutterButton.accessibilityLabel = "Shutter"
        view.addSubview(shutterButton)
        applyShutterAppearance(isLive: false, isRecording: false)
        setupShutterGestures()

        let symbol = UIImage.SymbolConfiguration(pointSize: 14, weight: .semibold)

        var flipConfig = UIButton.Configuration.plain()
        flipConfig.image = UIImage(
            systemName: "arrow.triangle.2.circlepath.camera",
            withConfiguration: symbol
        )
        flipConfig.baseForegroundColor = .white
        flipConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        flipConfig.cornerStyle = .capsule
        flipConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        flipButton.configuration = flipConfig
        flipButton.accessibilityLabel = "Flip Camera"
        flipButton.translatesAutoresizingMaskIntoConstraints = true
        flipButton.isUserInteractionEnabled = false
        view.addSubview(flipButton)

        var libraryConfig = UIButton.Configuration.plain()
        libraryConfig.image = UIImage(
            systemName: "photo.on.rectangle",
            withConfiguration: symbol
        )
        libraryConfig.baseForegroundColor = .white
        libraryConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        libraryConfig.cornerStyle = .capsule
        libraryConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        libraryButton.configuration = libraryConfig
        libraryButton.accessibilityLabel = "Camera Roll"
        libraryButton.accessibilityHint = "Opens Photos after a capture is saved"
        libraryButton.translatesAutoresizingMaskIntoConstraints = true
        libraryButton.isUserInteractionEnabled = false
        libraryButton.alpha = 0.55
        libraryButton.addTarget(
            self,
            action: #selector(libraryButtonTapped),
            for: .touchUpInside
        )
        view.addSubview(libraryButton)
    }

    /// Places camera-roll · shutter track · Flip as one horizontal row.
    ///
    /// Both Display Modes slide the same way — right → live, left → off. Vertical
    /// hangs the row under the panel; Landscape overlays the panel's bottom edge,
    /// where the panel already fills the screen height.
    func layoutBottomChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let inset: CGFloat = 20
        let controlSize = Self.chromeControlSize
        let pad = Self.shutterTrackPadding

        if !isShutterDragging, !isShutterSettling {
            shutterSlideProgress = isAirPlayLive ? 1 : 0
        }

        let trackSize = CGSize(
            width: Self.shutterSize + Self.shutterTrackTravel + pad * 2,
            height: Self.shutterSize + pad * 2
        )
        let rowY = ExternalOutputSettings.isVerticalMode
            ? panel.maxY + Self.verticalChromeGap
            : panel.maxY - inset - trackSize.height
        let sideY = rowY + (trackSize.height - controlSize) / 2

        shutterTrackFrame = CGRect(
            origin: CGPoint(x: panel.midX - trackSize.width / 2, y: rowY),
            size: trackSize
        )
        shutterTrackView.frame = shutterTrackFrame
        shutterTrackView.layer.cornerRadius = trackSize.height / 2

        libraryButton.frame = CGRect(
            x: panel.minX + inset,
            y: sideY,
            width: controlSize,
            height: controlSize
        )
        flipButton.frame = CGRect(
            x: panel.maxX - inset - controlSize,
            y: sideY,
            width: controlSize,
            height: controlSize
        )

        layoutShutterThumbInTrack()
        layoutShutterHint()

        view.bringSubviewToFront(shutterTrackView)
        view.bringSubviewToFront(libraryButton)
        view.bringSubviewToFront(shutterButton)
        view.bringSubviewToFront(flipButton)

        updateShutterAccessibilityHint()
    }

    /// Positions the shutter thumb from `shutterSlideProgress` inside the track.
    func layoutShutterThumbInTrack() {
        let track = shutterTrackFrame
        guard track.width > 1 else { return }
        let pad = Self.shutterTrackPadding
        let progress = min(1, max(0, shutterSlideProgress))
        shutterButton.frame = CGRect(
            x: track.minX + pad + Self.shutterTrackTravel * progress,
            y: track.minY + pad,
            width: Self.shutterSize,
            height: Self.shutterSize
        )
    }

    /// Updates LIVE badge and shutter for preview vs AirPlay-live.
    func refreshLiveChrome() {
        let live = isAirPlayLive
        let recording = CameraManager.shared.isRecording
        goLiveButton.isHidden = !live
        applyLiveBadgeAppearance()
        applyShutterAppearance(isLive: live, isRecording: recording)
        layoutTopChromeInPanel()
        layoutBottomChromeInPanel()
    }

    /// Whether AirPlay currently owns the camera overlay (including Logo park).
    var isAirPlayLive: Bool {
        ExternalDisplayManager.shared.isCameraModeActive
    }

    /// Styles the shutter for idle / live / recording.
    func applyShutterAppearance(isLive: Bool, isRecording: Bool) {
        var config = UIButton.Configuration.plain()
        config.cornerStyle = .capsule
        if isRecording {
            config.background.backgroundColor = .systemRed
            config.background.strokeColor = .white
            config.background.strokeWidth = 4
        } else if isLive {
            config.background.backgroundColor = .systemRed
            config.background.strokeColor = UIColor.white.withAlphaComponent(0.85)
            config.background.strokeWidth = 3
        } else {
            config.background.backgroundColor = .white
            config.background.strokeColor = UIColor.white.withAlphaComponent(0.35)
            config.background.strokeWidth = 3
        }
        shutterButton.configuration = config
        shutterButton.accessibilityValue = isRecording
            ? "Recording"
            : (isLive ? "Live" : "Preview")
    }

    func updateShutterAccessibilityHint() {
        shutterButton.accessibilityHint = isAirPlayLive
            ? "Tap for photo. Hold to record. Slide left to stop live."
            : "Slide right to go live on AirPlay."
    }

    // MARK: - Private

    private func applyLiveBadgeAppearance() {
        var config = UIButton.Configuration.filled()
        let dot = UIImage.SymbolConfiguration(pointSize: 6, weight: .bold)
        config.title = "LIVE"
        config.image = UIImage(systemName: "circle.fill", withConfiguration: dot)
        config.imagePadding = 6
        config.baseBackgroundColor = .systemRed
        config.baseForegroundColor = .white
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 8, leading: 12, bottom: 8, trailing: 12
        )
        goLiveButton.configuration = config
        goLiveButton.accessibilityLabel = "Live"
        goLiveButton.accessibilityHint = nil
    }
}
