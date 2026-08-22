//
//  CameraLiveViewController+PreviewSource.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Preview Source (hardware layer vs frame-tap mirror)

extension CameraLiveViewController {

    /// Wait before reclaiming the hardware preview after stop-live, covering the
    /// AirPlay crossfade out of camera.
    static let previewHandoffDelay: TimeInterval = 0.5
    /// Fallback if the mirror's first frame never arrives.
    static let mirrorFirstFrameTimeout: TimeInterval = 0.35
    /// Beat for `AVCaptureVideoPreviewLayer` to paint after reclaiming the session.
    static let hardwarePreviewPaintDelay: TimeInterval = 0.2

    /// Points the phone panel at whichever live source is available right now.
    ///
    /// The capture session drives a single `AVCaptureVideoPreviewLayer`, and binding a
    /// second one hands it the connection and blacks out the first. While AirPlay is
    /// live the TV owns that layer, so the panel mirrors the frame tap instead;
    /// off-air — and when live with no display — the panel takes the hardware layer.
    /// - Parameter force: Re-applies even when the source is unchanged (Display Mode
    ///   switches change gravity and rotation).
    func updateLivePreviewSource(force: Bool = false) {
        let shouldMirror = isAirPlayLive && ExternalDisplayManager.shared.isConnected
        guard force || isPreviewMirrored != shouldMirror else { return }
        // Cover only a real swap — not the first bind or a force re-layout.
        let sourceChanged =
            (isPreviewMirrored == false && shouldMirror)
            || (isPreviewMirrored == true && !shouldMirror)
        isPreviewMirrored = shouldMirror
        previewHandoffWorkItem?.cancel()
        previewHandoffWorkItem = nil

        guard !shouldMirror else {
            adoptMirrorPreview(coverHandoff: sourceChanged)
            return
        }
        // AirPlay tears its camera layer down behind a transition, so reclaiming the
        // hardware preview immediately would black out the TV mid-crossfade. The mirror
        // keeps the panel live until the TV has let go.
        if mirrorView.isMirroring {
            scheduleHardwarePreviewHandoff()
        } else {
            adoptHardwarePreview(coverHandoff: sourceChanged)
        }
    }

    /// Switches the phone panel to the frame-tap mirror *before* AirPlay attaches the
    /// hardware preview layer. Call this ahead of `presentCamera()` so the TV's attach
    /// does not black out the phone panel first.
    func prepareLivePreviewHandoffToAirPlay() {
        guard isPreviewMirrored != true else { return }
        isPreviewMirrored = true
        previewHandoffWorkItem?.cancel()
        previewHandoffWorkItem = nil
        adoptMirrorPreview(coverHandoff: true)
    }

    /// Releases the frame tap when the panel goes away.
    func teardownLivePreviewSource() {
        previewHandoffWorkItem?.cancel()
        previewHandoffWorkItem = nil
        mirrorView.onFirstFrame = nil
        mirrorView.stopMirroring()
        isPreviewMirrored = nil
    }

    /// Fills the panel with the mirror, rotating sensor frames to match live preview.
    ///
    /// Uses the lens horizon angle — Vertical is not always 90° (portrait-mounted front
    /// sensors report 0°). Landscape still only spins 0°/180° for Left vs Right.
    func layoutMirrorView() {
        guard !mirrorView.isHidden else { return }
        let degrees = CGFloat(
            CameraManager.shared.quantizedRotationAngle(
                CameraManager.shared.horizonLevelCaptureRotationAngle()
            )
        )
        if ExternalOutputSettings.isVerticalMode {
            PresentationViewController.applyRotatedLayout(
                to: mirrorView,
                in: panelView,
                scale: 1,
                rotationDegrees: degrees
            )
            return
        }
        mirrorView.bounds = CGRect(origin: .zero, size: panelView.bounds.size)
        mirrorView.center = CGPoint(x: panelView.bounds.midX, y: panelView.bounds.midY)
        mirrorView.transform = degrees == 0
            ? .identity
            : CGAffineTransform(rotationAngle: degrees * .pi / 180)
    }

    // MARK: - Private

    /// Covers the panel with the latest still so a source swap never flashes black.
    private func showHandoffFreezeFrame() {
        let image = CameraManager.shared.latestSampleImage
            ?? CameraManager.shared.lastFrame
        guard let image, !CameraManager.isNearlyBlack(image) else { return }
        freezeFrameView.image = image
        freezeFrameView.alpha = 1
        freezeFrameView.isHidden = false
        panelView.bringSubviewToFront(freezeFrameView)
        layoutFrameOverlay()
    }

    private func adoptMirrorPreview(coverHandoff: Bool) {
        if coverHandoff {
            showHandoffFreezeFrame()
            mirrorView.onFirstFrame = { [weak self] in
                self?.hideFreezeFrame()
            }
        }
        previewView.detach()
        previewView.isHidden = true
        mirrorView.isHidden = false
        mirrorView.startMirroring()
        layoutPhoneCameraViewport()
        guard coverHandoff else { return }
        // Safety net if the first sample stalls (permission race, etc.).
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.mirrorFirstFrameTimeout
        ) { [weak self] in
            self?.hideFreezeFrame()
        }
    }

    private func scheduleHardwarePreviewHandoff() {
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isPreviewMirrored == false else { return }
            self.adoptHardwarePreview(coverHandoff: true)
        }
        previewHandoffWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.previewHandoffDelay,
            execute: work
        )
    }

    /// Binds the panel to the session's one preview layer. Only safe off-air.
    private func adoptHardwarePreview(coverHandoff: Bool) {
        previewHandoffWorkItem = nil
        if coverHandoff {
            showHandoffFreezeFrame()
        }
        mirrorView.onFirstFrame = nil
        mirrorView.stopMirroring()
        mirrorView.isHidden = true
        previewView.isHidden = false
        // Panel aspect matches Display Mode — fill the card in both modes.
        previewView.attach(
            session: CameraManager.shared.captureSession,
            videoGravity: .resizeAspectFill
        )
        previewView.syncDisplayModeOrientation()
        layoutPhoneCameraViewport()
        guard coverHandoff else { return }
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.hardwarePreviewPaintDelay
        ) { [weak self] in
            self?.hideFreezeFrame()
        }
    }
}
