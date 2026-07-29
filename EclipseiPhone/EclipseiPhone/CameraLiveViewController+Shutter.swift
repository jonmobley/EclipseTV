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

    /// Wires pan on the shutter thumb (always a horizontal slide).
    func setupShutterGestures() {
        let pan = UIPanGestureRecognizer(
            target: self,
            action: #selector(handleShutterPan(_:))
        )
        pan.maximumNumberOfTouches = 1
        shutterButton.addGestureRecognizer(pan)
    }

    @objc func handleShutterPan(_ gesture: UIPanGestureRecognizer) {
        // Measured in `view`, which never moves — the track and thumb do.
        let axisDelta = gesture.translation(in: view).x
        switch gesture.state {
        case .began:
            isShutterDragging = true
            isShutterSettling = false
            shutterDidSlide = false
            shutterDidLongPress = false
            // Pinned once so a live-state change mid-drag can't shift the thumb.
            shutterDragBaseProgress = isAirPlayLive ? 1 : 0
            shutterSlideAnchor = 0
            shutterHoldTimer?.invalidate()
            shutterHoldTimer = nil
            if isAirPlayLive {
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
            // Both Display Modes: +x → live, −x → off.
            if !shutterDidSlide, abs(axisDelta) >= Self.shutterSlideThreshold {
                shutterDidSlide = true
                // Anchor where the slide was recognized so the dead zone isn't a jump.
                shutterSlideAnchor = axisDelta
                shutterHoldTimer?.invalidate()
                shutterHoldTimer = nil
                if shutterDidLongPress, CameraManager.shared.isRecording {
                    CameraManager.shared.stopRecording()
                    shutterDidLongPress = false
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
        guard track.width > 1 else { return }
        let pad = Self.shutterTrackPadding
        let size: CGFloat = 30
        let live = isAirPlayLive
        let symbol = UIImage.SymbolConfiguration(pointSize: 22, weight: .semibold)
        shutterHintView.image = UIImage(
            systemName: live ? "chevron.compact.left" : "chevron.compact.right",
            withConfiguration: symbol
        )
        shutterHintView.frame = CGRect(
            x: live ? track.minX + pad : track.maxX - pad - size,
            y: track.midY - size / 2,
            width: size,
            height: size
        )
        // The thumb is sliding over the chevron's side of the track — get out of the way.
        shutterHintView.alpha = isShutterDragging ? 0 : 0.5
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
        if wantLive {
            if !mgr.isCameraModeActive {
                mgr.presentCamera()
                warnIfNoExternalDisplay()
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            } else if mgr.isCameraParkedOnLogo {
                mgr.resumeCameraFromLogoPark()
            }
        } else if mgr.isCameraModeActive {
            if CameraManager.shared.isRecording {
                CameraManager.shared.stopRecording()
            }
            mgr.stopCameraAndApplyCloseDestination()
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        }
        // Settling first so the chrome refresh leaves the thumb where the finger left it.
        isShutterSettling = true
        refreshLiveChrome()
        snapShutterProgress(to: wantLive ? 1 : 0, animated: true)
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

    /// Live tap: save a still to Photos.
    func capturePhotoFromShutter() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        CameraManager.shared.capturePhotoToLibrary { [weak self] result in
            guard let self else { return }
            switch result {
            case .success:
                self.enableCameraRollButton()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                self.showCaptureError(error)
            }
        }
    }

    /// Hold while live: start a local recording.
    func beginShutterHoldRecord() {
        if ExternalDisplayManager.shared.isCameraParkedOnLogo {
            ExternalDisplayManager.shared.resumeCameraFromLogoPark()
        }
        refreshLiveChrome()
        UIImpactFeedbackGenerator(style: .heavy).impactOccurred()

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
        guard CameraManager.shared.isRecording else {
            refreshLiveChrome()
            return
        }
        CameraManager.shared.stopRecording { [weak self] result in
            guard let self else { return }
            self.refreshLiveChrome()
            switch result {
            case .success:
                self.enableCameraRollButton()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            case .failure(let error):
                self.showCaptureError(error)
            }
        }
    }

    /// Enables the camera-roll control after a successful save.
    func enableCameraRollButton() {
        libraryButton.isUserInteractionEnabled = true
        libraryButton.alpha = 1
    }

    @objc func libraryButtonTapped() {
        if let url = URL(string: "photos-redirect://") {
            UIApplication.shared.open(url)
        }
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
