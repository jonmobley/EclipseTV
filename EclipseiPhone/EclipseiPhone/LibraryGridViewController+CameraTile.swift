//
//  LibraryGridViewController+CameraTile.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Home Camera Tile Warm Preview

extension LibraryGridViewController {

    /// Starts capture when authorized so the idle Camera tile can show a live feed.
    /// Does not prompt for permission — fullscreen Camera owns that.
    ///
    /// Attaches the preview layer immediately (last-frame placeholder), then starts
    /// the session when the app is active. Retries are owned by `CameraManager`.
    func warmHomeCameraPreview() {
        // The tools row is Show-only; on Home there is no tile to feed.
        guard sectionIndex(for: .tools) != nil else { return }
        guard !ExternalDisplayManager.shared.isCameraModeActive else { return }
        guard AVCaptureDevice.authorizationStatus(for: .video) == .authorized else {
            return
        }
        // Fullscreen Camera is using the shared session — don't fight it.
        guard !isCameraControlPresented else { return }

        homeCameraWarmPreviewSuspended = false
        // Bind the tile to the session before startRunning so the first frames show.
        refreshVisibleCameraTilePreview()
        CameraManager.shared.prepareAndStart { [weak self] in
            guard let self, !self.isCameraControlPresented else { return }
            self.refreshVisibleCameraTilePreview()
        }
    }

    /// Freezes the Camera tile on a still before fullscreen Camera presents, so the
    /// shared preview layer handoff doesn't flash black under the animation.
    func parkHomeCameraTileForFullscreen() {
        homeCameraWarmPreviewSuspended = true
        if let cell = visibleCameraCell() {
            CameraManager.shared.captureLastFrame(from: cell.cameraPreview)
            cell.configureCamera(
                isLive: ExternalDisplayManager.shared.isCameraLive,
                lastFrame: CameraManager.shared.lastFrame,
                warmPreview: false
            )
        } else {
            CameraManager.shared.captureLastFrame(from: nil)
        }
    }

    /// Freezes + tears down the home tile preview when leaving the grid, unless
    /// fullscreen Camera or AirPlay still needs the session.
    func stopHomeCameraPreviewIfNeeded() {
        if ExternalDisplayManager.shared.isCameraModeActive { return }
        // Opening CameraLive — keep the warm session; don't blank the tile.
        if isCameraControlPresented { return }

        if let cell = visibleCameraCell() {
            CameraManager.shared.captureLastFrame(from: cell.cameraPreview)
            cell.parkCameraPreviewShowingLastFrame()
        }
        CameraManager.shared.stopSession()
    }

    /// Re-attaches the visible Camera tile after session start / Display Mode changes.
    func refreshVisibleCameraTilePreview() {
        guard !ExternalDisplayManager.shared.isCameraModeActive,
              !isCameraControlPresented,
              !homeCameraWarmPreviewSuspended,
              let cell = visibleCameraCell()
        else {
            return
        }
        cell.configureCamera(
            isLive: ExternalDisplayManager.shared.isCameraLive,
            lastFrame: CameraManager.shared.lastFrame,
            warmPreview: true
        )
        cell.refreshLiveCameraPreview()
    }

    /// Observes app-active + session-running so the tile stays live across launch
    /// and brief capture interruptions.
    func installHomeCameraPreviewObservers() {
        observe(UIApplication.didBecomeActiveNotification) { [weak self] _ in
            guard let self, self.isHomeCameraPreviewEligible else { return }
            self.warmHomeCameraPreview()
        }
        observe(CameraManager.sessionRunningDidChangeNotification) { [weak self] _ in
            guard let self, self.isHomeCameraPreviewEligible else { return }
            self.refreshVisibleCameraTilePreview()
        }
    }

    // MARK: - Private

    /// True when the home grid is on-screen and should own the warm camera preview.
    private var isHomeCameraPreviewEligible: Bool {
        guard isViewLoaded, view.window != nil else { return false }
        guard sectionIndex(for: .tools) != nil else { return false }
        guard !ExternalDisplayManager.shared.isCameraModeActive else { return false }
        guard !isCameraControlPresented else { return false }
        return true
    }

    /// Whether fullscreen Camera is presented anywhere above this grid.
    var isCameraControlPresented: Bool {
        if Self.findCameraLive(in: self) != nil { return true }
        if let root = view.window?.rootViewController,
           Self.findCameraLive(in: root) != nil {
            return true
        }
        // Walk parents — present() is usually from iPhoneMainViewController.
        var candidate: UIViewController? = parent
        while let current = candidate {
            if current.presentedViewController is CameraLiveViewController {
                return true
            }
            if Self.findCameraLive(in: current) != nil { return true }
            candidate = current.parent
        }
        return false
    }

    private static func findCameraLive(in root: UIViewController) -> CameraLiveViewController? {
        if let camera = root as? CameraLiveViewController { return camera }
        if let camera = root.presentedViewController as? CameraLiveViewController {
            return camera
        }
        if let presented = root.presentedViewController,
           let camera = findCameraLive(in: presented) {
            return camera
        }
        for child in root.children {
            if let camera = findCameraLive(in: child) { return camera }
        }
        return nil
    }

    private func visibleCameraCell() -> LibraryThumbnailCell? {
        guard let toolsSection = sectionIndex(for: .tools) else { return nil }
        let indexPath = IndexPath(item: 1, section: toolsSection)
        guard toolItems.indices.contains(1),
              case .camera = toolItems[1],
              let cell = collectionView.cellForItem(at: indexPath)
                as? LibraryThumbnailCell
        else {
            return nil
        }
        return cell
    }
}
