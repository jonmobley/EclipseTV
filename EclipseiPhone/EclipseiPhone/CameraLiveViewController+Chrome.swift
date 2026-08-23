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
        recordingTimerPillView.addSubview(recordingTimerLabel)
        view.addSubview(recordingTimerPillView)
        configureTapToGoLiveHint()
        view.addSubview(tapToGoLiveHintView)
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

        layoutRecordingTimerPill(in: panel)
        layoutTapToGoLiveHint(in: panel)
        view.bringSubviewToFront(tapToGoLiveHintView)
        view.bringSubviewToFront(backButton)
        view.bringSubviewToFront(goLiveButton)
        view.bringSubviewToFront(recordingTimerPillView)
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
        let live = Self.showsLiveBadge(
            isCameraLive: ExternalDisplayManager.shared.isCameraLive
        )
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

    /// LIVE pill is only for the live camera feed, not a parked cutaway still.
    static func showsLiveBadge(isCameraLive: Bool) -> Bool { isCameraLive }

    /// Hint is shown on open (preview) and while a cutaway still is on program.
    static func showsTapToGoLiveHint(isCameraLive: Bool) -> Bool { !isCameraLive }

    /// Builds the centered "Tap screen to go LIVE" overlay.
    private func configureTapToGoLiveHint() {
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseForegroundColor = .white
        config.baseBackgroundColor = UIColor.black.withAlphaComponent(0.45)
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 10, leading: 16, bottom: 10, trailing: 16
        )
        config.title = "Tap screen to go LIVE"
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer {
            var attrs = $0
            attrs.font = .systemFont(ofSize: 16, weight: .semibold)
            return attrs
        }
        tapToGoLiveHintView.configuration = config
        tapToGoLiveHintView.isUserInteractionEnabled = false
        tapToGoLiveHintView.accessibilityLabel = "Tap screen to go LIVE"
        tapToGoLiveHintView.translatesAutoresizingMaskIntoConstraints = true
    }

    /// Capsule elapsed-time pill, centered in the camera preview panel.
    private func layoutRecordingTimerPill(in panel: CGRect) {
        guard !recordingTimerPillView.isHidden else { return }
        let textSize = recordingTimerLabel.sizeThatFits(CGSize(width: 120, height: 36))
        let padX: CGFloat = 12
        let padY: CGFloat = 6
        let width = min(max(textSize.width + padX * 2, 56), panel.width - 32)
        let height = max(textSize.height + padY * 2, 28)
        recordingTimerPillView.layer.cornerRadius = height / 2
        recordingTimerPillView.clipsToBounds = true
        let y: CGFloat
        if goLiveButton.isHidden {
            y = goLiveButton.frame.minY
        } else {
            y = goLiveButton.frame.maxY + 8
        }
        recordingTimerPillView.frame = CGRect(
            x: panel.midX - width / 2,
            y: y,
            width: width,
            height: height
        )
        recordingTimerLabel.frame = recordingTimerPillView.bounds.insetBy(dx: padX, dy: padY)
    }

    /// Centers the go-live hint in the Display Mode panel.
    private func layoutTapToGoLiveHint(in panel: CGRect) {
        let show = Self.showsTapToGoLiveHint(
            isCameraLive: ExternalDisplayManager.shared.isCameraLive
        )
        tapToGoLiveHintView.isHidden = !show
        guard show else { return }
        var size = tapToGoLiveHintView.intrinsicContentSize
        if size.width < 8 || size.height < 8 {
            size = tapToGoLiveHintView.sizeThatFits(
                CGSize(width: panel.width - 32, height: 44)
            )
        }
        let width = min(max(size.width, 200), panel.width - 32)
        let height = max(size.height, 36)
        tapToGoLiveHintView.frame = CGRect(
            x: panel.midX - width / 2,
            y: panel.midY - height / 2,
            width: width,
            height: height
        )
    }
}
