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

    /// Places Back · centered LIVE · Settings over the panel (safe-area aware).
    func layoutTopChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        let inset: CGFloat = 18
        let controlSize = Self.chromeControlSize
        let rowY = max(panel.minY + inset, view.safeAreaInsets.top + 8)
        let leading = max(panel.minX + inset, view.safeAreaInsets.left + 12)
        let trailing = min(
            panel.maxX - inset - controlSize,
            view.bounds.maxX - view.safeAreaInsets.right - 12 - controlSize
        )

        backButton.frame = CGRect(
            x: leading,
            y: rowY,
            width: controlSize,
            height: controlSize
        )

        settingsButton.frame = CGRect(
            x: trailing,
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

    /// Builds shutter + Flip + Frame (docked outside the Display Mode panel).
    func setupCaptureMocks() {
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
            "Chooses which frames appear as overlay thumbnails on the camera"
        frameButton.translatesAutoresizingMaskIntoConstraints = true
        frameButton.addTarget(
            self,
            action: #selector(frameButtonTapped),
            for: .touchUpInside
        )
        view.addSubview(frameButton)
    }

    /// Places Frame · shutter · Flip in the outside dock (not over the preview).
    ///
    /// Vertical: bottom dock under the panel. Landscape: trailing dock — the same
    /// physical spot when the phone is held sideways.
    func layoutBottomChromeInPanel() {
        let panel = panelView.convert(panelView.bounds, to: view)
        guard panel.width > 1, panel.height > 1 else { return }

        if ExternalOutputSettings.isVerticalMode {
            layoutVerticalCaptureChrome(panel: panel)
        } else {
            layoutLandscapeCaptureChrome(panel: panel)
        }

        view.bringSubviewToFront(frameButton)
        view.bringSubviewToFront(shutterButton)
        view.bringSubviewToFront(flipButton)
        layoutAlternateStillButton(panel: panel)
        refreshAlternateStillAppearance()
        layoutLiveOutputThumb(panel: panel)
        layoutFrameRibbon(panel: panel)

        updateShutterAccessibilityHint()
    }

    /// Frame · shutter · Flip in a row in the bottom dock under the Vertical panel.
    private func layoutVerticalCaptureChrome(panel: CGRect) {
        let inset: CGFloat = 20
        let controlSize = Self.chromeControlSize
        let bottomPad = max(8, view.safeAreaInsets.bottom)
        let rowY = view.bounds.maxY - bottomPad - Self.shutterSize
        let sideY = rowY + (Self.shutterSize - controlSize) / 2

        shutterButton.frame = CGRect(
            x: panel.midX - Self.shutterSize / 2,
            y: rowY,
            width: Self.shutterSize,
            height: Self.shutterSize
        )
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

    /// Same chrome as Vertical, in the trailing dock beside the Landscape panel.
    private func layoutLandscapeCaptureChrome(panel: CGRect) {
        let inset: CGFloat = 20
        let controlSize = Self.chromeControlSize
        let trailingPad = max(8, view.safeAreaInsets.right)
        let colX = view.bounds.maxX - trailingPad - Self.shutterSize
        let sideX = colX + (Self.shutterSize - controlSize) / 2

        shutterButton.frame = CGRect(
            x: colX,
            y: panel.midY - Self.shutterSize / 2,
            width: Self.shutterSize,
            height: Self.shutterSize
        )
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

    /// Whether AirPlay currently owns the camera overlay (including still park).
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
        if !isAirPlayLive {
            shutterButton.accessibilityHint = "Tap for photo. Hold to record."
            return
        }
        if ExternalOutputSettings.alwaysRecordWhenLive {
            shutterButton.accessibilityHint =
                "Tap for photo. Recording starts with live. "
                + "Tap the preview to stop live and recording."
        } else {
            shutterButton.accessibilityHint =
                "Tap for photo. Hold to record. Tap the preview to stop live."
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
