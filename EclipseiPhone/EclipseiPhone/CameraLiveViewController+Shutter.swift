//
//  CameraLiveViewController+Shutter.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Shutter (slide = live, tap = photo, hold = video)

extension CameraLiveViewController {

    /// Hold duration before a press becomes a recording (seconds).
    static let shutterHoldDuration: TimeInterval = 0.35
    /// Movement (pt) before a press counts as a slide, not a tap/hold.
    static let shutterSlideThreshold: CGFloat = 12
    /// Progress above this commits to live when the drag ends.
    static let shutterLiveCommitProgress: CGFloat = 0.55

    /// Wires press+drag on the shutter thumb (axis follows Display Mode).
    ///
    /// Uses a zero-duration long-press rather than a pan: `UIPanGestureRecognizer`
    /// only begins after the finger moves, so stationary tap/hold never fired.
    func setupShutterGestures() {
        let press = UILongPressGestureRecognizer(
            target: self,
            action: #selector(handleShutterPress(_:))
        )
        press.minimumPressDuration = 0
        // Default allowableMovement (~10pt) would cancel before a slide completes.
        press.allowableMovement = .greatestFiniteMagnitude
        shutterButton.addGestureRecognizer(press)
    }

    @objc func handleShutterPress(_ gesture: UILongPressGestureRecognizer) {
        // Measured in `view`, which never moves — the track and thumb do.
        // Vertical: +x → live. Landscape: +y → live (toward Flip on the right strip).
        let location = gesture.location(in: view)
        switch gesture.state {
        case .began:
            isShutterDragging = true
            isShutterSettling = false
            shutterDidSlide = false
            shutterDidLongPress = false
            shutterTouchOrigin = location
            // Pinned once so a live-state change mid-drag can't shift the thumb.
            shutterDragBaseProgress = isAirPlayLive ? 1 : 0
            shutterSlideAnchor = 0
            shutterHoldTimer?.invalidate()
            shutterHoldTimer = nil
            // Always-record mode owns start/stop with live; hold would fight that.
            if isAirPlayLive, !ExternalOutputSettings.alwaysRecordWhenLive {
                shutterHoldTimer = Timer.scheduledTimer(
                    withTimeInterval: Self.shutterHoldDuration,
                    repeats: false
                ) { [weak self] _ in
                    guard let self, !self.shutterDidSlide else { return }
                    self.shutterDidLongPress = true
                    self.beginShutterHoldRecord()
                }
            }

        case .changed:
            let axisDelta = shutterAxisDelta(from: location)
            if !shutterDidSlide, abs(axisDelta) >= Self.shutterSlideThreshold {
                shutterDidSlide = true
                // Anchor where the slide was recognized so the dead zone isn't a jump.
                shutterSlideAnchor = axisDelta
                shutterHoldTimer?.invalidate()
                shutterHoldTimer = nil
                // Sliding replaces release-to-stop: finalize the movie, then the
                // drag can still commit on/off live when the finger lifts.
                if CameraManager.shared.isRecording {
                    shutterDidLongPress = false
                    finalizeRecordingIfNeeded()
                }
            }
            guard shutterDidSlide else { return }
            trackShutterThumb(toTranslation: axisDelta)

        case .ended, .cancelled, .failed:
            shutterHoldTimer?.invalidate()
            shutterHoldTimer = nil
            isShutterDragging = false
            finishShutterGesture()
            shutterDidSlide = false
            shutterDidLongPress = false

        default:
            break
        }
    }

    /// Axis travel since press began (Display Mode–aware).
    private func shutterAxisDelta(from location: CGPoint) -> CGFloat {
        if ExternalOutputSettings.isVerticalMode {
            return location.x - shutterTouchOrigin.x
        }
        return location.y - shutterTouchOrigin.y
    }

    /// Moves the thumb with the finger, re-anchoring at each rail.
    ///
    /// Re-anchoring keeps the thumb glued to the finger: without it, overshooting
    /// an end banks travel that has to be paid back before the thumb moves again.
    private func trackShutterThumb(toTranslation axisDelta: CGFloat) {
        let travel = Self.shutterTrackTravel
        let raw = shutterDragBaseProgress + (axisDelta - shutterSlideAnchor) / travel
        let clamped = min(1, max(0, raw))
        if raw != clamped {
            shutterSlideAnchor =
                axisDelta - (clamped - shutterDragBaseProgress) * travel
        }
        shutterSlideProgress = clamped
        layoutShutterThumbInTrack()
        layoutShutterHint()
    }

    /// Points the track chevron at the end the next slide travels toward.
    func layoutShutterHint() {
        let track = shutterTrackView.bounds
        guard track.width > 1, track.height > 1 else { return }
        let pad = Self.shutterTrackPadding
        let size: CGFloat = 30
        let live = isAirPlayLive
        let vertical = ExternalOutputSettings.isVerticalMode
        let symbol = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        let name: String
        if vertical {
            name = live ? "chevron.compact.left" : "chevron.compact.right"
        } else {
            name = live ? "chevron.compact.up" : "chevron.compact.down"
        }
        shutterHintView.image = UIImage(systemName: name, withConfiguration: symbol)
        // Idle: red cue toward live. Live: white cue toward stop.
        shutterHintView.tintColor = live ? .white : .systemRed
        if vertical {
            shutterHintView.frame = CGRect(
                x: live ? track.minX + pad : track.maxX - pad - size,
                y: track.midY - size / 2,
                width: size,
                height: size
            )
        } else {
            shutterHintView.frame = CGRect(
                x: track.midX - size / 2,
                y: live ? track.minY + pad : track.maxY - pad - size,
                width: size,
                height: size
            )
        }
        // The thumb is sliding over the chevron's side of the track — get out of the way.
        shutterHintView.alpha = isShutterDragging ? 0 : (live ? 0.5 : 0.85)
    }

    /// Commits slide → live/stop, or tap → photo / hold → stop record.
    private func finishShutterGesture() {
        if shutterDidSlide {
            commitShutterSlide()
            return
        }
        guard isAirPlayLive else {
            // Preview: no tap action — must slide toward live.
            snapShutterProgress(to: 0, animated: true)
            return
        }
        if shutterDidLongPress {
            endShutterHoldRecord()
        } else {
            capturePhotoFromShutter()
        }
    }

    private func commitShutterSlide() {
        let wantLive = shutterSlideProgress >= Self.shutterLiveCommitProgress
        let mgr = ExternalDisplayManager.shared
        // Before handoff/chrome layout — those would otherwise snap progress to 0/1.
        isShutterSettling = true
        if wantLive {
            if !mgr.isCameraModeActive {
                // Mirror first — AirPlay's attach steals the one preview connection.
                prepareLivePreviewHandoffToAirPlay()
                mgr.presentCamera()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else if mgr.isCameraParkedOnLogo {
                mgr.resumeCameraFromLogoPark()
            }
            refreshLiveChrome()
            snapShutterProgress(to: 1, animated: true)
            startAlwaysLiveRecordingIfNeeded()
            return
        }

        guard mgr.isCameraModeActive else {
            refreshLiveChrome()
            snapShutterProgress(to: 0, animated: true)
            return
        }

        // Off-live: finish any movie first so Photos gets a complete file, then leave.
        finalizeRecordingIfNeeded { [weak self] in
            guard let self else { return }
            ExternalDisplayManager.shared.stopCameraAndApplyCloseDestination()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            self.refreshLiveChrome()
            self.snapShutterProgress(to: 0, animated: true)
        }
    }

    private func snapShutterProgress(to value: CGFloat, animated: Bool) {
        shutterSlideProgress = value
        guard animated else {
            isShutterSettling = false
            layoutShutterThumbInTrack()
            layoutShutterHint()
            return
        }
        isShutterSettling = true
        // Fades the chevron back in at its new end as the thumb travels.
        shutterHintView.alpha = 0
        UIView.animate(
            withDuration: 0.28,
            delay: 0,
            usingSpringWithDamping: 0.86,
            initialSpringVelocity: 0,
            options: [.beginFromCurrentState, .allowUserInteraction],
            animations: {
                self.layoutShutterThumbInTrack()
                self.layoutShutterHint()
            },
            completion: { [weak self] _ in
                self?.isShutterSettling = false
            }
        )
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
    /// Used by release-to-stop, slide-while-recording, slide-off-live, and Back.
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
