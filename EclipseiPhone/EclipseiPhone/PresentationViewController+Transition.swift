//
//  PresentationViewController+Transition.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Dual-Layer Content Transition

extension PresentationViewController {

    /// Starts a dual-layer transition: underlay keeps playing, incoming builds in
    /// `transitionOverlayContainer` at alpha 0, then Cut/Crossfade reveals it.
    func performContentTransition(to source: PresentationSource) {
        AudioAmbientPolicy.applyYieldIfNeeded(for: source)

        transitionFallbackWorkItem?.cancel()
        transitionFallbackWorkItem = nil
        clearIncomingOverlay(animated: false)

        transitionGeneration += 1
        let generation = transitionGeneration
        pendingTransitionSource = source
        isTransitionInFlight = true
        isRevealScheduled = false

        if case .video = source.content {
            isPresentingVideo = true
        } else {
            isPresentingVideo = false
        }

        ensureTransitionOverlay()
        transitionOverlayContainer.alpha = 0
        transitionOverlayContainer.isHidden = false
        view.bringSubviewToFront(transitionOverlayContainer)
        view.bringSubviewToFront(messageLabel)
        view.bringSubviewToFront(activityIndicator)
        if let badge = audioNowPlayingBadge {
            view.bringSubviewToFront(badge)
        }
        installIncoming(source, generation: generation)

        let fallback = DispatchWorkItem { [weak self] in
            self?.revealIncomingAndCommit(generation: generation)
        }
        transitionFallbackWorkItem = fallback
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: fallback)
    }

    /// Incoming content has something to show — reveal overlay, then promote to primary.
    func notifyContentReadyForTransition() {
        guard isTransitionInFlight, !isCommittingTransition else { return }
        revealIncomingAndCommit(generation: transitionGeneration)
    }

    /// Reveals the overlay (Cut or Crossfade), installs into primary, clears overlay.
    func revealIncomingAndCommit(generation: Int) {
        guard generation == transitionGeneration, isTransitionInFlight, !isRevealScheduled else {
            return
        }
        guard let source = pendingTransitionSource else { return }

        transitionFallbackWorkItem?.cancel()
        transitionFallbackWorkItem = nil
        isRevealScheduled = true

        let commit = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            // Promote under an opaque overlay so primary rebuild never flashes.
            self.isCommittingTransition = true
            self.applyShowDirect(source)
            self.isCommittingTransition = false
            self.finishCommitWhenPrimaryVisible(source: source, generation: generation)
        }

        if ExternalOutputSettings.contentTransition == .crossfade {
            UIView.animate(
                withDuration: 0.35,
                delay: 0,
                options: [.curveEaseInOut, .beginFromCurrentState]
            ) {
                self.transitionOverlayContainer.alpha = 1
            } completion: { _ in
                commit()
            }
        } else {
            transitionOverlayContainer.alpha = 1
            commit()
        }
    }

    /// Drops the overlay once the primary surface has a frame (video) or immediately.
    private func finishCommitWhenPrimaryVisible(
        source: PresentationSource,
        generation: Int
    ) {
        let finish = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            guard self.isTransitionInFlight else { return }
            self.clearIncomingOverlay(animated: false)
            self.pendingTransitionSource = nil
            self.isTransitionInFlight = false
            self.isRevealScheduled = false
            self.refreshAudioNowPlayingOverlay()
        }

        if case .camera = source.content {
            DispatchQueue.main.asyncAfter(
                deadline: .now() + CameraLiveViewController.hardwarePreviewPaintDelay
            ) {
                finish()
            }
            return
        }

        if case .screensaver = source.content {
            waitUntilScreensaverDisplayed(generation: generation, then: finish)
            return
        }

        guard case .video = source.content,
              let layer = playerLayer, !layer.isReadyForDisplay else {
            finish()
            return
        }
        videoReadyObservation = layer.observe(\.isReadyForDisplay, options: [.new]) {
            [weak self] layer, _ in
            guard layer.isReadyForDisplay else { return }
            DispatchQueue.main.async {
                self?.videoReadyObservation = nil
                finish()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard self?.videoReadyObservation != nil else { return }
            self?.videoReadyObservation = nil
            finish()
        }
    }

    /// Holds the overlay until the primary Screensaver has a displayed frame.
    private func waitUntilScreensaverDisplayed(
        generation: Int,
        then finish: @escaping () -> Void
    ) {
        let complete = { [weak self] in
            guard let self, generation == self.transitionGeneration else { return }
            self.screensaverView?.onReady = nil
            finish()
        }
        guard let view = screensaverView, !view.isReadyForDisplay else {
            complete()
            return
        }
        view.onReady = { complete() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0, execute: complete)
    }

    /// Ensures the fullscreen incoming host exists and is pinned to the view.
    func ensureTransitionOverlay() {
        if transitionOverlayContainer.superview == nil {
            transitionOverlayContainer.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(transitionOverlayContainer)
            NSLayoutConstraint.activate([
                transitionOverlayContainer.topAnchor.constraint(equalTo: view.topAnchor),
                transitionOverlayContainer.bottomAnchor.constraint(equalTo: view.bottomAnchor),
                transitionOverlayContainer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
                transitionOverlayContainer.trailingAnchor.constraint(equalTo: view.trailingAnchor)
            ])
        }
    }

    /// Removes incoming views and hides the overlay host.
    func clearIncomingOverlay(animated: Bool) {
        incomingImageRequest?.cancel()
        incomingImageRequest = nil
        incomingVideoReadyObservation = nil
        incomingLayerReadyObservation = nil
        incomingWebNavigation = nil

        if let loop = incomingLoopObserver {
            NotificationCenter.default.removeObserver(loop)
            incomingLoopObserver = nil
        }
        incomingPlayer?.pause()
        incomingPlayer = nil
        incomingPlayerLayer?.removeFromSuperlayer()
        incomingPlayerLayer = nil

        incomingScreensaverView?.stop()
        incomingScreensaverView?.removeFromSuperview()
        incomingScreensaverView = nil

        incomingCameraPreview?.detach()
        incomingCameraPreview?.removeFromSuperview()
        incomingCameraPreview = nil
        incomingCameraFrameOverlay?.removeFromSuperview()
        incomingCameraFrameOverlay = nil

        discardIncomingWebView()

        incomingPDFView?.document = nil
        incomingPDFView?.removeFromSuperview()
        incomingPDFView = nil

        incomingImageView?.removeFromSuperview()
        incomingImageView = nil
        incomingMediaHost?.removeFromSuperview()
        incomingMediaHost = nil

        let hide = {
            self.transitionOverlayContainer.alpha = 0
            self.transitionOverlayContainer.isHidden = true
            self.transitionOverlayContainer.subviews.forEach { $0.removeFromSuperview() }
        }
        if animated {
            UIView.animate(withDuration: 0.15, animations: {
                self.transitionOverlayContainer.alpha = 0
            }, completion: { _ in hide() })
        } else {
            hide()
        }
    }
}
