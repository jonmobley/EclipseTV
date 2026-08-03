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
        view.addSubview(goLiveButton)
        view.addSubview(recordingTimerLabel)
        applyLiveBadgeAppearance()
    }

    /// Places Back · centered LIVE · Settings inside the panel.
    func layoutTopChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let inset: CGFloat = 18
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

        // Fixed size for LIVE so the pill doesn't jump when chrome re-layouts.
        let goSize = CGSize(width: 78, height: 28)
        let goY = rowY + (controlSize - goSize.height) / 2
        goLiveButton.frame = CGRect(
            x: panel.midX - goSize.width / 2,
            y: goY,
            width: goSize.width,
            height: goSize.height
        )

        // Timer sits just right of LIVE while recording (hidden otherwise).
        let timerSize = recordingTimerLabel.sizeThatFits(
            CGSize(width: 80, height: goSize.height)
        )
        recordingTimerLabel.frame = CGRect(
            x: goLiveButton.frame.maxX + 8,
            y: goY,
            width: max(timerSize.width, 36),
            height: goSize.height
        )

        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(goLiveButton)
        view.bringSubviewToFront(recordingTimerLabel)
        view.bringSubviewToFront(settingsButton)
    }

    /// Builds shutter track + thumb + Flip + Frame.
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
        flipButton.isEnabled = CameraManager.shared.canFlipCamera
        flipButton.addTarget(
            self,
            action: #selector(flipButtonTapped),
            for: .touchUpInside
        )
        view.addSubview(flipButton)

        var frameConfig = UIButton.Configuration.plain()
        frameConfig.image = UIImage(
            systemName: "rectangle.dashed",
            withConfiguration: symbol
        )
        frameConfig.baseForegroundColor = .white
        frameConfig.background.backgroundColor = UIColor.black.withAlphaComponent(0.45)
        frameConfig.cornerStyle = .capsule
        frameConfig.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 10, bottom: 10, trailing: 10
        )
        frameButton.configuration = frameConfig
        frameButton.accessibilityLabel = "Frames"
        frameButton.accessibilityHint =
            "Chooses a frame overlay, or imports and deletes frames"
        frameButton.translatesAutoresizingMaskIntoConstraints = true
        frameButton.addTarget(
            self,
            action: #selector(frameButtonTapped),
            for: .touchUpInside
        )
        view.addSubview(frameButton)
    }

    /// Places Frame · shutter track · Flip along the phone's bottom edge.
    ///
    /// Vertical: horizontal row under the panel (slide right → live). Landscape:
    /// vertical column on the right of the panel — same physical spot when the phone
    /// is held sideways (slide down → live). Glyphs stay upright in both modes
    /// (Landscape Display Mode already rotates the interface).
    func layoutBottomChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        if !isShutterDragging, !isShutterSettling {
            shutterSlideProgress = isAirPlayLive ? 1 : 0
        }

        if ExternalOutputSettings.isVerticalMode {
            layoutVerticalCaptureChrome(panel: panel)
        } else {
            layoutLandscapeCaptureChrome(panel: panel)
        }

        layoutShutterThumbInTrack()
        layoutShutterHint()

        view.bringSubviewToFront(shutterTrackView)
        view.bringSubviewToFront(frameButton)
        view.bringSubviewToFront(shutterButton)
        view.bringSubviewToFront(flipButton)

        updateShutterAccessibilityHint()
    }

    /// Frame · shutter · Flip in a row under the Vertical panel.
    private func layoutVerticalCaptureChrome(panel: CGRect) {
        let inset: CGFloat = 20
        let controlSize = Self.chromeControlSize
        let pad = Self.shutterTrackPadding
        let trackSize = CGSize(
            width: Self.shutterSize + Self.shutterTrackTravel + pad * 2,
            height: Self.shutterSize + pad * 2
        )
        let rowY = panel.maxY + Self.chromeGap
        let sideY = rowY + (trackSize.height - controlSize) / 2

        shutterTrackFrame = CGRect(
            origin: CGPoint(x: panel.midX - trackSize.width / 2, y: rowY),
            size: trackSize
        )
        shutterTrackView.frame = shutterTrackFrame
        shutterTrackView.layer.cornerRadius = trackSize.height / 2

        frameButton.frame = CGRect(
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
        flipButton.transform = .identity
    }

    /// Same chrome as Vertical, rotated onto the right of the Landscape panel.
    private func layoutLandscapeCaptureChrome(panel: CGRect) {
        let inset: CGFloat = 20
        let controlSize = Self.chromeControlSize
        let pad = Self.shutterTrackPadding
        // Portrait row stood on end: short side is width, travel runs vertically.
        let trackSize = CGSize(
            width: Self.shutterSize + pad * 2,
            height: Self.shutterSize + Self.shutterTrackTravel + pad * 2
        )
        let colX = panel.maxX + Self.chromeGap
        let sideX = colX + (trackSize.width - controlSize) / 2

        shutterTrackFrame = CGRect(
            origin: CGPoint(x: colX, y: panel.midY - trackSize.height / 2),
            size: trackSize
        )
        shutterTrackView.frame = shutterTrackFrame
        shutterTrackView.layer.cornerRadius = trackSize.width / 2

        frameButton.frame = CGRect(
            x: sideX,
            y: panel.minY + inset,
            width: controlSize,
            height: controlSize
        )
        flipButton.frame = CGRect(
            x: sideX,
            y: panel.maxY - inset - controlSize,
            width: controlSize,
            height: controlSize
        )
        flipButton.transform = .identity
    }

    /// Positions the shutter thumb from `shutterSlideProgress` inside the track.
    func layoutShutterThumbInTrack() {
        let track = shutterTrackFrame
        guard track.width > 1, track.height > 1 else { return }
        let pad = Self.shutterTrackPadding
        let progress = min(1, max(0, shutterSlideProgress))
        if ExternalOutputSettings.isVerticalMode {
            shutterButton.frame = CGRect(
                x: track.minX + pad + Self.shutterTrackTravel * progress,
                y: track.minY + pad,
                width: Self.shutterSize,
                height: Self.shutterSize
            )
        } else {
            shutterButton.frame = CGRect(
                x: track.minX + pad,
                y: track.minY + pad + Self.shutterTrackTravel * progress,
                width: Self.shutterSize,
                height: Self.shutterSize
            )
        }
    }

    /// Updates LIVE badge and shutter for preview vs AirPlay-live.
    func refreshLiveChrome() {
        // Going live hands the hardware preview layer to the TV — re-route the panel.
        updateLivePreviewSource()
        let live = isAirPlayLive
        let recording = CameraManager.shared.isRecording
        applyLiveBadgeAppearance()
        applyShutterAppearance(isLive: live, isRecording: recording)
        refreshFlipButtonEnabled()
        syncRecordingTimer()
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
        let towardLive = ExternalOutputSettings.isVerticalMode ? "right" : "down"
        let towardOff = ExternalOutputSettings.isVerticalMode ? "left" : "up"
        guard isAirPlayLive else {
            shutterButton.accessibilityHint =
                "Slide \(towardLive) to go live on AirPlay."
            return
        }
        if ExternalOutputSettings.alwaysRecordWhenLive {
            shutterButton.accessibilityHint =
                "Tap for photo. Recording starts with live. "
                + "Slide \(towardOff) to stop live and recording."
        } else {
            shutterButton.accessibilityHint =
                "Tap for photo. Hold to record. Slide \(towardOff) to stop live."
        }
    }

    /// Flips front ↔ back camera.
    @objc func flipButtonTapped() {
        guard CameraManager.shared.canFlipCamera else { return }
        if CameraManager.shared.isRecording {
            showPresentationToast(
                "Stop recording to flip camera",
                centeredIn: panelView
            )
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        flipButton.isEnabled = false
        CameraManager.shared.flipCamera { [weak self] in
            self?.refreshFlipButtonEnabled()
        }
    }

    /// Flip stays available except while recording or when only one camera exists.
    func refreshFlipButtonEnabled() {
        let camera = CameraManager.shared
        let allowed = camera.canFlipCamera && !camera.isRecording
        flipButton.isEnabled = allowed
        flipButton.alpha = allowed ? 1 : 0.45
        flipButton.accessibilityHint = camera.isRecording
            ? "Unavailable while recording"
            : "Switches between the front and back cameras"
    }

    // MARK: - Private

    private func applyLiveBadgeAppearance() {
        let live = isAirPlayLive
        goLiveButton.isHidden = !live
        goLiveButton.isUserInteractionEnabled = false
        guard live else {
            goLiveButton.configuration = nil
            return
        }
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: 10, bottom: 4, trailing: 10
        )
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 11, weight: .semibold)
            return attrs
        }
        config.baseForegroundColor = .white
        let dot = UIImage.SymbolConfiguration(pointSize: 5, weight: .bold)
        config.title = "LIVE"
        config.image = UIImage(systemName: "circle.fill", withConfiguration: dot)
        config.imagePadding = 4
        config.baseBackgroundColor = .systemRed
        goLiveButton.accessibilityLabel = "Live"
        goLiveButton.accessibilityHint = nil
        goLiveButton.configuration = config
    }
}
