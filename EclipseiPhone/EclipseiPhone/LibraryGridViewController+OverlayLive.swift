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

    /// Camera tile tap: go live, or open the controller when already live.
    ///
    /// Opening the viewfinder does not touch output, so the lock does not gate it.
    /// A remote operator never presents locally, so its tile is never live here and
    /// the tap falls through to `presentCameraLiveOnOutput` to command the director.
    func presentCameraFromTile() {
        switch CameraStillRibbon.cameraTileTap(
            isCameraTileLive: ExternalDisplayManager.shared.isCameraTileLive
        ) {
        case .openController:
            Haptics.impactLight()
            onPresentCamera?()
        case .goLive:
            presentCameraLiveOnOutput()
        }
    }

    /// Puts Camera live on the grid without opening the controller.
    ///
    /// The no-UI path, matching `presentWebPageLive` / `presentPDFLive`: an
    /// operator's tap applied on the director must not pop a viewfinder there.
    /// A tile tap goes through `presentCameraFromTile` instead, and the phone
    /// viewfinder also opens from the live preview tap or ⋯ Open Controller.
    func presentCameraLiveOnOutput() {
        guard !blockLiveChangeIfLocked() else { return }
        if sendShowLiveSelectIfOperator(.camera, itemId: nil) {
            Haptics.impactLight()
            return
        }
        if ExternalDisplayManager.shared.isCameraTileLive {
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

    /// Opens the phone browser or PDF reader for the website / PDF currently live.
    ///
    /// Reached from the live preview tap. The browser adopts the warm page, so the
    /// hero falls back to a static thumbnail while it is up.
    func presentControllerForLiveOverlay() {
        let mgr = ExternalDisplayManager.shared
        if mgr.isWebLive,
           let pageId = mgr.liveWebPageId,
           let page = WebPageStore.shared.page(id: pageId) {
            presentWebPage(page)
            return
        }
        if mgr.isPDFLive,
           let doc = PDFStore.shared.documents.first(where: { $0.id == mgr.livePDFDocumentId }) {
            presentPDF(doc)
        }
    }

    /// Marks a saved website live without opening the phone browser.
    ///
    /// Used where phone UI must not appear: an operator's tap applied on the
    /// director, Countdown reaching 0:00, and video links. A card tap opens the
    /// browser via `presentWebPage` instead.
    ///
    /// YouTube / Vimeo / direct-file URLs play edge-to-edge instead of loading
    /// the desktop watch page.
    func presentWebPageLive(_ page: WebPage) {
        guard !blockLiveChangeIfLocked() else { return }
        guard hasLiveOutputDestination else { return }
        if sendShowLiveSelectIfOperator(.web, itemId: page.id.uuidString) {
            Haptics.impactLight()
            return
        }
        let mgr = ExternalDisplayManager.shared
        if let link = page.videoLink {
            if mgr.isWebVideoLive, mgr.liveWebVideoPageId == page.id {
                return
            }
            SlideshowPlaybackController.shared.stop()
            mgr.presentWebVideo(link, pageId: page.id)
            announceAirPlayOverlayIfLinked()
            Haptics.impactLight()
            reloadLibraryGrid()
            refreshLiveHeader()
            return
        }
        if mgr.isWebLive, mgr.liveWebPageId == page.id {
            return
        }
        SlideshowPlaybackController.shared.stop()
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        mgr.presentWeb(page.url, pageId: page.id)
        announceAirPlayOverlayIfLinked()
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Marks a saved PDF live without opening the phone reader.
    ///
    /// Used where phone UI must not appear: an operator's tap applied on the
    /// director and Countdown reaching 0:00. A card tap opens the reader via
    /// `presentPDF` instead.
    func presentPDFLive(_ doc: SavedPDF) {
        guard !blockLiveChangeIfLocked() else { return }
        guard hasLiveOutputDestination else { return }
        if sendShowLiveSelectIfOperator(.pdf, itemId: doc.id.uuidString) {
            Haptics.impactLight()
            return
        }
        let mgr = ExternalDisplayManager.shared
        if mgr.isPDFLive, mgr.livePDFDocumentId == doc.id {
            return
        }
        guard let url = resolvedPDFFileURL(for: doc) else { return }
        SlideshowPlaybackController.shared.stop()
        mgr.presentPDF(url, documentId: doc.id)
        announceAirPlayOverlayIfLinked()
        Haptics.impactLight()
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
        Haptics.impactLight()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    private func presentCameraPermissionNeededAlert() {
        Haptics.error()
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
