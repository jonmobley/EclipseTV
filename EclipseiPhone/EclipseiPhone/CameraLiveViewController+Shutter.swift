//
//  CameraLiveViewController+Shutter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Shutter (tap stage = live, shutter tap = photo, hold = video)

extension CameraLiveViewController {

    /// Hold duration before a press becomes a recording (seconds).
    static let shutterHoldDuration: TimeInterval = 0.35

    /// Wires press on the shutter thumb (tap = photo, hold = record while live).
    ///
    /// Uses a zero-duration long-press rather than a pan: `UIPanGestureRecognizer`
    /// only begins after the finger moves, so stationary tap/hold never fired.
    func setupShutterGestures() {
        let press = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleShutterPress(_:))
        )
        press.minimumPressDuration = 0
        press.allowableMovement = .greatestFiniteMagnitude
        shutterButton.addGestureRecognizer(press)
    }

    /// Tap the stage (outside chrome) to toggle AirPlay live.
    @objc func handleStageTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: view)
        // Chrome lives on `view` above the stage — ignore those hits.
        if hitTestBlocksStageLiveToggle(at: location) { return }
        toggleAirPlayLive()
    }

    /// True when the tap landed on a chrome control that owns the gesture.
    private func hitTestBlocksStageLiveToggle(at location: CGPoint) -> Bool {
        let blockers: [UIView] = [
            backButton, settingsButton, shutterButton, flipButton, frameButton
        ]
        return blockers.contains { $0.frame.contains(location) && !$0.isHidden }
    }

    @objc func handleShutterPress(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            shutterDidLongPress = false
            shutterHoldTimer?.invalidate()
            shutterHoldTimer = nil
            // Always-record mode owns start/stop with live; hold would fight that.
            guard isAirPlayLive, !ExternalOutputSettings.alwaysRecordWhenLive else { return }
            shutterHoldTimer = Timer.scheduledTimer(
                withTimeInterval: Self.shutterHoldDuration,
                repeats: false
            ) { [weak self] _ in
                guard let self else { return }
                self.shutterDidLongPress = true
                self.beginShutterHoldRecord()
            }

        case .ended, .cancelled, .failed:
            shutterHoldTimer?.invalidate()
            shutterHoldTimer = nil
            finishShutterGesture()
            shutterDidLongPress = false

        default:
            break
        }
    }

    /// Tap → photo while live; hold release → stop record. Idle: no shutter action.
    private func finishShutterGesture() {
        guard isAirPlayLive else { return }
        if shutterDidLongPress {
            endShutterHoldRecord()
        } else {
            capturePhotoFromShutter()
        }
    }

    /// Goes live on AirPlay, or stops live (and finishes any movie first).
    func toggleAirPlayLive() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnLogo {
            mgr.resumeCameraFromLogoPark()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            refreshLiveChrome()
            startAlwaysLiveRecordingIfNeeded()
            return
        }
        if mgr.isCameraModeActive {
            finalizeRecordingIfNeeded { [weak self] in
                guard let self else { return }
                ExternalDisplayManager.shared.stopCameraAndApplyCloseDestination()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                self.refreshLiveChrome()
            }
            return
        }

        // Mirror first — AirPlay's attach steals the one preview connection.
        prepareLivePreviewHandoffToAirPlay()
        mgr.presentCamera()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshLiveChrome()
        startAlwaysLiveRecordingIfNeeded()
    }

    /// Live tap: blink the panel and save a still to Photos.
    func capturePhotoFromShutter() {
        playShutterBlink()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        CameraManager.shared.capturePhotoToLibrary { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(let image):
                self.fileStillInLibrary(image)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                self.showCaptureError(error)
            }
        }
    }

    /// Brief black flash over the camera panel (classic shutter feedback).
    func playShutterBlink() {
        let flash = UIView(frame: panelView.bounds)
        flash.backgroundColor = .black
        flash.isUserInteractionEnabled = false
        panelView.addSubview(flash)
        // Sit above preview/mirror; frame overlay can stay readable on top.
        if frameOverlayView.superview === panelView {
            panelView.insertSubview(flash, belowSubview: frameOverlayView)
        }
        flash.alpha = 1
        UIView.animate(
            withDuration: 0.14,
            delay: 0.03,
            options: [.curveEaseOut],
            animations: { flash.alpha = 0 },
            completion: { _ in flash.removeFromSuperview() }
        )
    }

    /// Hold while live: start a local recording.
    func beginShutterHoldRecord() {
        if ExternalDisplayManager.shared.isCameraParkedOnLogo {
            ExternalDisplayManager.shared.resumeCameraFromLogoPark()
        }
        refreshLiveChrome()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        startRecordingFromShutter()
    }

    /// Starts recording when Always Record When Live is on and camera is on AirPlay.
    ///
    /// No-ops if the preference is off, camera isn't live, a movie is already rolling,
    /// or a modal (e.g. Camera Settings) is covering the shutter. Used after go-live,
    /// settings dismiss, and preference changes.
    func startAlwaysLiveRecordingIfNeeded() {
        guard ExternalOutputSettings.alwaysRecordWhenLive else { return }
        guard ExternalDisplayManager.shared.isCameraLive else { return }
        guard !CameraManager.shared.isRecording else { return }
        guard presentedViewController == nil else { return }
        startRecordingFromShutter()
    }

    /// Starts a movie and refreshes chrome / surfaces capture errors.
    private func startRecordingFromShutter() {
        CameraManager.shared.startRecording { [weak self] result in
            guard let self else { return }
            self.refreshLiveChrome()
            if case .failure(let error) = result {
                self.showCaptureError(error)
            }
        }
    }

    /// Release after hold: stop recording; stay live.
    func endShutterHoldRecord() {
        finalizeRecordingIfNeeded()
    }

    /// Stops an in-flight movie, keeps it for in-app review, then runs `completion`.
    ///
    /// Used by release-to-stop, stop-live, and Back.
    func finalizeRecordingIfNeeded(completion: (() -> Void)? = nil) {
        guard CameraManager.shared.isRecording else {
            refreshLiveChrome()
            completion?()
            return
        }
        shutterHoldTimer?.invalidate()
        shutterHoldTimer = nil
        shutterDidLongPress = false
        CameraManager.shared.stopRecording { [weak self] result in
            guard let self else {
                completion?()
                return
            }
            // Read before `refreshLiveChrome()` — that stops the timer and clears the start.
            let elapsed = self.recordingStartedAt.map { Date().timeIntervalSince($0) } ?? 0
            self.refreshLiveChrome()
            switch result {
            case .success(let previewURL):
                if let previewURL {
                    self.fileMovieInLibrary(at: previewURL, duration: elapsed)
                }
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                self.showCaptureError(error)
            }
            completion?()
        }
    }

    // MARK: - Recording timer

    /// Shows/hides and ticks the elapsed label beside LIVE.
    func syncRecordingTimer() {
        if CameraManager.shared.isRecording {
            if recordingStartedAt == nil {
                recordingStartedAt = Date()
            }
            recordingTimerLabel.isHidden = false
            updateRecordingTimerLabel()
            guard recordingTickTimer == nil else { return }
            recordingTickTimer = Timer.scheduledTimer(
                withTimeInterval: 0.25,
                repeats: true
            ) { [weak self] _ in
                self?.updateRecordingTimerLabel()
            }
        } else {
            stopRecordingTimer()
        }
    }

    /// Clears the LIVE elapsed timer.
    func stopRecordingTimer() {
        recordingTickTimer?.invalidate()
        recordingTickTimer = nil
        recordingStartedAt = nil
        recordingTimerLabel.isHidden = true
        recordingTimerLabel.text = nil
    }

    private func updateRecordingTimerLabel() {
        guard let start = recordingStartedAt else {
            recordingTimerLabel.text = "0:00"
            return
        }
        let elapsed = max(0, Int(Date().timeIntervalSince(start)))
        let minutes = elapsed / 60
        let seconds = elapsed % 60
        recordingTimerLabel.text = String(format: "%d:%02d", minutes, seconds)
        layoutTopChromeInPanel()
    }

    private func showCaptureError(_ error: Error) {
        let alert = UIAlertController(
            title: "Capture Failed",
            message: error.localizedDescription,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
