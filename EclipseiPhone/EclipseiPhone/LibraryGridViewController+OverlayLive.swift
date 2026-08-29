//
//  LibraryGridViewController+OverlayLive.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import UIKit

// MARK: - Camera / Web / PDF Live (Stay on Grid)

extension LibraryGridViewController {

    /// Puts Camera on AirPlay / Practice without opening the phone viewfinder.
    func presentCameraLiveOnOutput() {
        guard !blockLiveChangeIfLocked() else { return }
        guard hasLiveOutputDestination else { return }
        if ExternalDisplayManager.shared.isCameraTileLive {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        SlideshowPlaybackController.shared.stop()
        Task { @MainActor [weak self] in
            await self?.startCameraLiveOnOutput()
        }
    }

    /// Marks a saved website live without opening the phone browser.
    func presentWebPageLive(_ page: WebPage) {
        guard !blockLiveChangeIfLocked() else { return }
        guard hasLiveOutputDestination else { return }
        let mgr = ExternalDisplayManager.shared
        if mgr.isWebLive, mgr.liveWebPageId == page.id {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        SlideshowPlaybackController.shared.stop()
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        mgr.presentWeb(page.url, pageId: page.id)
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Marks a saved PDF live without opening the phone reader.
    func presentPDFLive(_ doc: SavedPDF) {
        guard !blockLiveChangeIfLocked() else { return }
        guard hasLiveOutputDestination else { return }
        let mgr = ExternalDisplayManager.shared
        if mgr.isPDFLive, mgr.livePDFDocumentId == doc.id {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard let url = resolvedPDFFileURL(for: doc) else { return }
        SlideshowPlaybackController.shared.stop()
        mgr.presentPDF(url, documentId: doc.id)
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// File URL for a saved PDF, or an alert if the file is gone.
    func resolvedPDFFileURL(for doc: SavedPDF) -> URL? {
        if let url = PDFStore.shared.fileURL(for: doc.id) { return url }
        let alert = UIAlertController(
            title: "PDF Missing",
            message: "That file is no longer on this iPhone.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
        return nil
    }

    // MARK: - Camera Session

    /// Marks Background live after Camera closed while parked on that still.
    func adoptBackgroundSelectionIfCameraCommitted() {
        let mgr = ExternalDisplayManager.shared
        guard !mgr.isCameraModeActive, mgr.isShowingBackgroundStill else { return }
        isBlackSelected = false
        isScreensaverSelected = false
        isLogoSelected = true
        store.updateCurrentId(nil)
    }

    /// Requests permission, starts capture if needed, then pushes Camera live.
    private func startCameraLiveOnOutput() async {
        let granted = await CameraManager.shared.checkPermissions()
        guard granted else {
            presentCameraPermissionNeededAlert()
            return
        }
        guard view.window != nil else { return }
        if CameraManager.shared.isSessionRunning {
            finishPresentingCameraLiveOnOutput()
            return
        }
        CameraManager.shared.prepareAndStart { [weak self] in
            self?.finishPresentingCameraLiveOnOutput()
        }
    }

    /// Unbinds the tile preview so AirPlay can take the one hardware layer.
    private func finishPresentingCameraLiveOnOutput() {
        guard view.window != nil else { return }
        if let cell = visibleCameraCell() {
            CameraManager.shared.captureLastFrame(from: cell.cameraPreview)
        }
        HomeCameraTilePreview.shared.unbind()
        ExternalDisplayManager.shared.presentCamera()
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    private func presentCameraPermissionNeededAlert() {
        let alert = UIAlertController(
            title: "Camera Access Needed",
            message: "Enable camera access in Settings to use the camera.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { _ in
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
        })
        present(alert, animated: true)
    }
}
