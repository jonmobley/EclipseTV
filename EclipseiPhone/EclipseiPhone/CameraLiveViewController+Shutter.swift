//
//  CameraLiveViewController+Shutter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Capture (tap stage = live, photo shutter, tap record)

extension CameraLiveViewController {

    /// Wires tap on the photo shutter and the record button.
    func setupCaptureButtons() {
        photoButton.addTarget(
            self,
            action: #selector(photoButtonTapped),
            for: .touchUpInside
        )
        shutterButton.addTarget(
            self,
            action: #selector(recordButtonTapped),
            for: .touchUpInside
        )
    }

    /// Tap the stage (outside chrome) to toggle live.
    @objc func handleStageTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let location = gesture.location(in: view)
        // Chrome lives on `view` above the stage — ignore those hits.
        if hitTestBlocksStageLiveToggle(at: location) { return }
        toggleAirPlayLive()
    }

    /// Activates the same go-live path as a stage tap (VoiceOver / direct tap).
    @objc func tapToGoLiveHintTapped() {
        toggleAirPlayLive()
    }

    /// True when the tap landed on a chrome control that owns the gesture.
    private func hitTestBlocksStageLiveToggle(at location: CGPoint) -> Bool {
        let blockers: [UIView] = [
            backButton, settingsButton, shutterButton, photoButton, flipButton,
            frameButton, stillRibbonView, frameRibbonView, tapToGoLiveHintView
        ]
        return blockers.contains { $0.frame.contains(location) && !$0.isHidden }
    }

    /// Saves a still. Works in preview, live, and while a movie is recording.
    @objc func photoButtonTapped() {
        capturePhotoFromShutter()
    }

    /// Tap to start or stop a local recording. Always Record When Live owns
    /// start/stop while on-air, so the record control is a no-op in that case.
    @objc func recordButtonTapped() {
        if isAirPlayLive, ExternalOutputSettings.alwaysRecordWhenLive { return }
        if CameraManager.shared.isRecording {
            finalizeRecordingIfNeeded()
        } else {
            startRecordingFromRecordButton()
        }
    }

    /// Goes live from preview. No-op when already live.
    ///
    /// Parked cutaway: resumes the live camera. Requires AirPlay, EclipseTV, or
    /// Practice Mode to go live the first time; otherwise the stage stays a
    /// viewfinder — the same Preview-only rule as Show cards.
    func toggleAirPlayLive() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isCameraParkedOnStill {
            mgr.resumeCameraFromStillPark()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            refreshLiveChrome()
            startAlwaysLiveRecordingIfNeeded()
            return
        }
        if mgr.isCameraModeActive {
            return
        }

        let practice = captureDestinationShowId.flatMap {
            LocalAlbumStore.shared.album(id: $0)?.previewsWhenDisconnected
        } ?? false
        guard LiveOutputRouting.canMarkLive(practiceMode: practice) else { return }

        // Mirror first — AirPlay's attach steals the one preview connection.
        if mgr.isConnected {
            prepareLivePreviewHandoffToAirPlay()
        }
        mgr.presentCamera()
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        refreshLiveChrome()
        startAlwaysLiveRecordingIfNeeded()
    }

    /// Blink the panel and save a still to Photos (and the Eclipse library).
    ///
    /// Safe while a movie is rolling: stills come from the video data output, which
    /// keeps delivering samples while `AVCaptureMovieFileOutput` is writing.
    func capturePhotoFromShutter() {
        if resumeCameraIfParkedOnStill() {
            refreshLiveChrome()
        }
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

    /// Starts a local recording (preview or live).
    func startRecordingFromRecordButton() {
        resumeCameraIfParkedOnStill()
        refreshLiveChrome()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        startRecordingFromShutter()
    }

    /// Restores the live camera when parked on a cutaway still.
    ///
    /// Returns `true` if a park was cleared. Does not call `presentCamera()` —
    /// a local (no-display) park only drops the cutaway stroke.
    @discardableResult
    private func resumeCameraIfParkedOnStill() -> Bool {
        guard ExternalDisplayManager.shared.isCameraParkedOnStill else { return false }
        ExternalDisplayManager.shared.resumeCameraFromStillPark()
        return true
    }

    /// Starts recording when Always Record When Live is on and camera is on AirPlay.
    ///
    /// No-ops if the preference is off, camera isn't live, a movie is already rolling,
    /// or a modal (e.g. Camera Settings) is covering the record control. Used after
    /// go-live, settings dismiss, and preference changes.
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

    /// Stops an in-flight movie, keeps it for in-app review, then runs `completion`.
    ///
    /// Used by tap-to-stop, stop-live, and Back.
    func finalizeRecordingIfNeeded(completion: (() -> Void)? = nil) {
        guard CameraManager.shared.isRecording else {
            refreshLiveChrome()
            completion?()
            return
        }
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

    /// Shows/hides and ticks the elapsed pill in the camera preview.
    func syncRecordingTimer() {
        if CameraManager.shared.isRecording {
            if recordingStartedAt == nil {
                recordingStartedAt = Date()
            }
            recordingTimerPillView.isHidden = false
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
        recordingTimerPillView.isHidden = true
        recordingTimerLabel.text = nil
    }

    private func updateRecordingTimerLabel() {
        if let start = recordingStartedAt {
            let elapsed = max(0, Int(Date().timeIntervalSince(start)))
            let minutes = elapsed / 60
            let seconds = elapsed % 60
            recordingTimerLabel.text = String(format: "%d:%02d", minutes, seconds)
        } else {
            recordingTimerLabel.text = "0:00"
        }
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
