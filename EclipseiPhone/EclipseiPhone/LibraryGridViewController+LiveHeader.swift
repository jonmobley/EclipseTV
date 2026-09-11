//
//  LibraryGridViewController+LiveHeader.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Header

extension LibraryGridViewController {
    /// Updates the fixed hero banner to reflect the currently live item (or a placeholder).
    ///
    /// Home uses the marketing carousel only — the live preview must stay hidden
    /// there. Blackout chrome still updates so the header moon reflects live state.
    func refreshLiveHeader() {
        let mgr = ExternalDisplayManager.shared
        // Every go-live path ends here, so this is where the director publishes
        // program to operators (deduped inside the session).
        broadcastShowLiveSnapshotIfNeeded()
        // An operator's header moon reflects the director's program, not local flags.
        let remoteSnapshot = ShowLiveSession.shared.isRemoteOperator
            ? ShowLiveSession.shared.snapshot : nil
        let blackLive = remoteSnapshot?.isBlackout
            ?? (isBlackSelected && !mgr.isOverlayLive)
        onBlackLiveChanged?(blackLive)
        onLiveOutputLockChanged?(isLiveOutputLocked)
        onLivePollPhoneHeroChanged?(isLivePollPhoneHeroActive)
        liveHeader.setOutputLocked(isLiveOutputLocked)
        guard showsLiveHero else {
            // Never leave a Show-mode live preview over the Home marketing carousel.
            liveHeader.clearWebPreview(parking: true)
            liveHeader.clearScreensaverPreview()
            liveHeader.clearLibraryVideoPreview()
            liveHeader.clearCameraPreview()
            liveHeader.setSlideshowRibbonToggleVisible(false, isOn: false)
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            liveHeader.setCameraFlipVisible(false)
            liveHeader.allowsSlideshowBrowse = false
            liveHeader.allowsLibraryBrowse = false
            liveHeader.isHidden = true
            liveHeader.isUserInteractionEnabled = false
            refreshForeignLivePreview()
            syncSlideshowRibbonIfChromeChanged()
            syncLiveNoteChrome()
            return
        }
        liveHeader.isHidden = false
        liveHeader.isUserInteractionEnabled = true
        // Ribbon, Screen Fit, Flip Camera, swipe browse, and the note follow the
        // active still / slideshow / camera. Browse runs last: it defers to the
        // ribbon's `allowsSlideshowBrowse` when a slideshow owns the gesture.
        defer {
            syncSlideshowRibbonIfChromeChanged()
            syncLiveScreenFitChrome()
            syncLiveCameraFlipChrome()
            syncLiveHeroBrowseChrome()
            syncLiveNoteChrome()
        }

        // Operator: the hero is a follow monitor for the director's program.
        if let remoteSnapshot {
            refreshForeignLivePreview()
            applyRemoteLiveHeader(remoteSnapshot)
            return
        }

        // Another Show still owns live output — keep AirPlay as-is, show an empty
        // hero here, and park the live art in the tucked mini preview.
        if isLiveFromOtherShow {
            liveHeader.configureSelectToGoLive()
            liveHeader.updatePlayback(PlaybackState())
            refreshForeignLivePreview()
            updateHeroCollapse()
            return
        }
        refreshForeignLivePreview()

        if applyLivePollPracticeHeaderIfNeeded() {
            return
        }
        if mgr.isWebLive {
            if mgr.isQuestPollLive {
                applyQuestPollLiveHeader()
                return
            }
            let pageId = mgr.liveWebPageId
            let page = pageId.flatMap { WebPageStore.shared.page(id: $0) }
            let title = page?.title ?? "Website"
            let thumb = pageId.flatMap { WebThumbnailStore.shared.image(for: $0) }
            let canShowLivePreview = pageId.map {
                !WarmWebSessionPool.shared.isAdopted(pageId: $0)
            } ?? false
            liveHeader.configureOverlay(
                title: title,
                systemImage: "safari",
                fillColor: .mediaPlaceholder,
                thumbnail: thumb,
                keepWebPreview: canShowLivePreview
            )
            if let pageId, canShowLivePreview {
                // In-app hero shows the warm page even with no AirPlay display.
                liveHeader.showWebPreview(pageId: pageId)
            }
            // Only a saved bookmark can be handed to the phone browser.
            liveHeader.allowsOverlayControllerTap = page != nil
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isWebVideoLive {
            let pageId = mgr.liveWebVideoPageId
            let page = pageId.flatMap { WebPageStore.shared.page(id: $0) }
            let title = page?.title ?? page?.videoLink?.providerName ?? "Video"
            let thumb = pageId.flatMap { WebThumbnailStore.shared.image(for: $0) }
            liveHeader.configureOverlay(
                title: title,
                systemImage: "play.rectangle.fill",
                fillColor: .mediaPlaceholder,
                thumbnail: thumb,
                showsTransport: true
            )
            liveHeader.updatePlayback(mgr.libraryVideoPlaybackState)
            return
        }
        if mgr.isPDFLive {
            let doc = PDFStore.shared.documents
                .first(where: { $0.id == mgr.livePDFDocumentId })
            let title = doc?.title ?? "PDF"
            let thumb = doc.flatMap { PDFThumbnailStore.shared.image(for: $0.id) }
            liveHeader.configureOverlay(
                title: title,
                systemImage: "doc.richtext",
                fillColor: .mediaPlaceholder,
                thumbnail: thumb
            )
            // Only a saved document can be handed to the phone reader.
            liveHeader.allowsOverlayControllerTap = doc != nil
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isCameraLive {
            presentCameraInLiveHeader()
            return
        }
        if mgr.isParkedOnQuickChangeStill {
            liveHeader.configureOverlay(
                title: "Camera",
                systemImage: "camera.fill",
                fillColor: .mediaPlaceholder,
                thumbnail: mgr.cameraTileParkedStillImage
            )
            liveHeader.allowsCameraControllerTap = true
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if mgr.isCountdownLive {
            applyCountdownLiveHeader()
            return
        }
        if isBlackSelected {
            liveHeader.configureOverlay(
                title: "Blackout",
                systemImage: "moon.fill",
                fillColor: .black
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isLogoSelected {
            liveHeader.configureOverlay(
                title: "Background",
                systemImage: "seal.fill",
                fillColor: .mediaPlaceholder,
                thumbnail: LogoStore.shared.image
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if isScreensaverSelected {
            presentScreensaverInLiveHeader()
            return
        }

        let liveItem = store.currentId.flatMap { id in
            store.items.first(where: { $0.id == id })
        }
        // AirPlay with nothing selected: preview the passive Screensaver filling
        // the external display. Practice Mode uses the same fallback.
        // EclipseTV-only still shows the connect prompt.
        if liveItem == nil, mgr.isConnected
            || (prefersDisconnectedLivePreview && !store.isOnline) {
            presentScreensaverInLiveHeader()
            return
        }
        if let liveItem, liveItem.isVideo {
            applyLibraryVideoLiveHeader(item: liveItem)
            return
        }
        let thumbnail = liveItem.flatMap { store.thumbnail(for: $0.id) }
        liveHeader.configure(
            with: liveItem,
            thumbnail: thumbnail,
            isOnline: store.isOnline
        )
        liveHeader.clearLibraryVideoPreview()
        liveHeader.updatePlayback(store.playback)
    }

    /// Opens fullscreen Preview for phone-local live media.
    func presentFullscreenForLiveMedia() {
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }),
              let url = LocalMediaStore.shared.localURL(forId: id) else { return }
        if item.isVideo {
            let startAt = liveHeader.libraryVideoPlaybackState.currentTime
            liveHeader.pauseLibraryVideoPreview()
            presentLocalVideoPreview(
                fileURL: url,
                isMuted: item.isMuted ?? false,
                isLooping: item.isLooping ?? false,
                startAt: startAt
            ) { [weak self] position in
                self?.liveHeader.resumeLibraryVideoPreview(at: position)
            }
            return
        }
        presentLocalPreview(
            for: item,
            in: openShowItems.isEmpty ? displayItems : openShowItems
        )
    }

    /// Live camera feed in the hero; the Camera tile shows the icon instead.
    ///
    /// Practice Mode has no AirPlay `AVCaptureVideoPreviewLayer`, so the hero
    /// mirrors the same frame tap the TV uses. A freeze still covers the glyph
    /// until the first sample arrives.
    private func presentCameraInLiveHeader() {
        let freeze = CameraManager.shared.latestSampleImage
            ?? CameraManager.shared.lastFrame
        let thumb = freeze.flatMap { CameraManager.isNearlyBlack($0) ? nil : $0 }
        liveHeader.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: .mediaPlaceholder,
            thumbnail: thumb,
            keepCameraPreview: liveHeader.isCameraPreviewActive
        )
        liveHeader.showCameraPreview()
        liveHeader.allowsCameraControllerTap = true
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Static poster chrome + muted looping video in the phone preview.
    private func presentScreensaverInLiveHeader() {
        liveHeader.configureOverlay(
            title: "Screensaver",
            systemImage: "sparkles.tv",
            fillColor: .mediaPlaceholder,
            thumbnail: ScreensaverStore.poster,
            keepScreensaverPreview: liveHeader.screensaverPreview != nil
        )
        liveHeader.showScreensaverPreview()
        liveHeader.updatePlayback(PlaybackState())
    }
}
