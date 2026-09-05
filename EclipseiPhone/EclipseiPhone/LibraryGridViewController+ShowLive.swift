//
//  LibraryGridViewController+ShowLive.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Second-device live remote

extension LibraryGridViewController {

    /// Aligns `eclipse-live` with the open Show and HDMI, then refreshes chrome.
    func syncShowLiveSession() {
        ShowLiveSession.shared.sync(openShowId: openShowId)
        if ShowLiveSession.shared.isDirector {
            broadcastShowLiveSnapshotIfNeeded()
        }
    }

    /// Sends `select` to the director. True when the caller must skip local present.
    @discardableResult
    func sendShowLiveSelectIfOperator(
        _ kind: ShowLiveItemKind,
        itemId: String?
    ) -> Bool {
        guard ShowLiveRouting.shouldCommandDirector(
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator
        ) else { return false }
        _ = ShowLiveSession.shared.sendSelect(kind: kind, itemId: itemId)
        reloadLibraryGrid()
        return true
    }

    /// Applies an operator tap on the director through existing `present*` paths.
    func applyIncomingShowLiveSelect(kind: ShowLiveItemKind, itemId: String?) {
        guard ShowLiveSession.shared.isDirector else { return }
        switch kind {
        case .media:
            guard let itemId,
                  let item = store.items.first(where: { $0.id == itemId })
            else { return }
            presentMedia(item)
        case .web:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let page = WebPageStore.shared.page(id: uuid) else { return }
            presentWebPageLive(page)
        case .pdf:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let doc = PDFStore.shared.documents.first(where: { $0.id == uuid })
            else { return }
            presentPDFLive(doc)
        case .camera:
            presentCameraLiveOnOutput()
        case .countdown:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let item = CountdownStore.shared.countdown(id: uuid) else { return }
            // Tile-tap semantics: pause/resume when already live, else go live.
            beginCountdown(item)
        case .slideshow:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let show = SlideshowStore.shared.slideshow(id: uuid) else { return }
            SlideshowPlaybackController.shared.play(
                show, connectionManager: connectionManager, startingAt: 0
            )
            reloadLibraryGrid()
            refreshLiveHeader()
        case .logo:
            presentLogoLive()
        case .screensaver:
            presentScreensaverLive()
        case .livePoll:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let item = LivePollStore.shared.poll(id: uuid) else { return }
            if QuestPollSessionStore.shared.membershipId == item.id,
               QuestPollSessionStore.shared.session != nil {
                selectLivePoll(item)
            } else {
                // No local tap to answer the hero gate, so skip straight to Start.
                // Replacing a live room still confirms on the director.
                startLivePoll(item)
            }
        case .black:
            // Toggle, not set: the wire has no "un-black", and the operator's moon
            // already shows the director's state from the snapshot.
            toggleBlackLive()
        }
    }

    /// Live stroke from the director snapshot instead of local program state.
    func isShowGridItemLiveRemotely(_ item: ShowGridItem) -> Bool {
        guard let snap = ShowLiveSession.shared.snapshot, !snap.isBlackout else {
            return false
        }
        switch item {
        case .slideshow(let show):
            return snap.liveKind == .slideshow
                && snap.liveItemId == show.id.uuidString
        case .screensaver:
            return snap.liveKind == .screensaver
        case .logo:
            return snap.liveKind == .logo
        case .camera:
            return snap.liveKind == .camera
        case .livePoll(let poll):
            return snap.liveKind == .livePoll
                && snap.liveItemId == poll.id.uuidString
        case .countdown(let countdown):
            return snap.liveKind == .countdown
                && snap.liveItemId == countdown.id.uuidString
        case .media(let media):
            return snap.liveKind == .media && snap.liveItemId == media.id
        case .website(let page):
            return snap.liveKind == .web && snap.liveItemId == page.id.uuidString
        case .pdf(let doc):
            return snap.liveKind == .pdf && snap.liveItemId == doc.id.uuidString
        case .unresolved, .add:
            return false
        }
    }

    /// Follow-monitor hero for an operator (no local camera / web / video player).
    func applyRemoteLiveHeader(_ snap: ShowLiveSnapshot) {
        liveHeader.clearWebPreview(parking: true)
        liveHeader.clearScreensaverPreview()
        liveHeader.clearCameraPreview()
        liveHeader.clearLibraryVideoPreview()
        liveHeader.hideLivePollGate()
        liveHeader.setSlideshowRibbonToggleVisible(false, isOn: false)
        liveHeader.setScreenFitToggleVisible(false, mode: .fit)
        liveHeader.allowsSlideshowBrowse = false
        if snap.isBlackout || snap.liveKind == .black {
            liveHeader.configureOverlay(
                title: "Blackout",
                systemImage: "moon.fill",
                fillColor: .black,
                showsLiveBadge: true
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        applyRemoteLiveHeaderContent(snap)
        liveHeader.updatePlayback(remotePlaybackState(snap))
    }

    /// Pushes current program to operators after a local go-live.
    func broadcastShowLiveSnapshotIfNeeded() {
        guard ShowLiveSession.shared.isDirector, let showId = openShowId else {
            return
        }
        ShowLiveSession.shared.broadcastSnapshot(makeShowLiveSnapshot(showId: showId))
    }

    func handleShowLiveSessionChanged(_ note: Notification) {
        if ShowLiveSession.shared.isRemoteOperator,
           let snap = ShowLiveSession.shared.snapshot {
            isLiveOutputLocked = snap.isLocked
        }
        // Video / clock ticks arrive about once a second; only the hero and the
        // live countdown tile need them, not a grid rebuild.
        let programChanged = note.userInfo?[ShowLiveSession.programChangedKey]
            as? Bool ?? true
        guard programChanged else {
            refreshLiveHeader()
            updateVisibleCountdownTiles()
            return
        }
        updateHeroVisibility()
        reloadLibraryGrid()
        refreshLiveHeader()
        onOpenShowChanged?(openShow)
    }

    func handleIncomingShowLiveSelect(_ note: Notification) {
        guard let raw = note.userInfo?[ShowLiveSession.selectKindKey] as? String,
              let kind = ShowLiveItemKind(rawValue: raw) else { return }
        let itemId = note.userInfo?[ShowLiveSession.selectItemIdKey] as? String
        applyIncomingShowLiveSelect(kind: kind, itemId: itemId)
    }
}

// MARK: - Snapshot

extension LibraryGridViewController {
    func makeShowLiveSnapshot(showId: UUID) -> ShowLiveSnapshot {
        let mgr = ExternalDisplayManager.shared
        let name = UIDevice.current.name
        if isBlackSelected && !mgr.isOverlayLive {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: nil, liveKind: .black,
                isBlackout: true, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if mgr.isCameraTileLive {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: nil, liveKind: .camera,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if mgr.isCountdownLive, let id = CountdownController.shared.liveCountdownId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: id.uuidString, liveKind: .countdown,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name,
                countdown: showLiveCountdownState
            )
        }
        if mgr.isQuestPollLive, let id = QuestPollSessionStore.shared.membershipId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: id.uuidString, liveKind: .livePoll,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if mgr.isWebLive, let pageId = mgr.liveWebPageId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: pageId.uuidString, liveKind: .web,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if mgr.isPDFLive, let docId = mgr.livePDFDocumentId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: docId.uuidString, liveKind: .pdf,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if let slideshowId = SlideshowPlaybackController.shared.activeSlideshowId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: slideshowId.uuidString,
                liveKind: .slideshow,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if isLogoSelected {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: nil, liveKind: .logo,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if isScreensaverSelected {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: nil, liveKind: .screensaver,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
            )
        }
        if let id = store.currentId {
            return ShowLiveSnapshot(
                showId: showId, liveItemId: id, liveKind: .media,
                isBlackout: false, isLocked: isLiveOutputLocked, directorName: name,
                video: showLiveVideoState
            )
        }
        return ShowLiveSnapshot(
            showId: showId, liveItemId: nil, liveKind: nil,
            isBlackout: false, isLocked: isLiveOutputLocked, directorName: name
        )
    }

    private func applyRemoteLiveHeaderContent(_ snap: ShowLiveSnapshot) {
        switch snap.liveKind {
        case .media:
            let item = snap.liveItemId.flatMap { id in
                store.items.first(where: { $0.id == id })
            }
            // Transport shows for video; taps go to the director as commands.
            liveHeader.configure(
                with: item,
                thumbnail: item.flatMap { store.thumbnail(for: $0.id) },
                isOnline: true,
                showsLocalTransport: item?.isVideo == true,
                usesRemoteVideoMonitor: item?.isVideo == true,
                showsLiveBadge: true
            )
        case .web:
            applyRemoteOverlayHeader(
                title: remoteWebTitle(snap.liveItemId),
                systemImage: "safari",
                thumbnail: remoteWebThumb(snap.liveItemId)
            )
        case .pdf:
            applyRemoteOverlayHeader(
                title: remotePDFTitle(snap.liveItemId),
                systemImage: "doc.richtext",
                thumbnail: remotePDFThumb(snap.liveItemId)
            )
        case .camera:
            applyRemoteOverlayHeader(title: "Camera", systemImage: "camera.fill")
        case .countdown:
            applyRemoteCountdownHeader(snap)
        case .slideshow:
            applyRemoteOverlayHeader(
                title: remoteSlideshowTitle(snap.liveItemId),
                systemImage: "rectangle.stack.fill"
            )
        case .logo:
            applyRemoteOverlayHeader(
                title: "Background",
                systemImage: "seal.fill",
                thumbnail: LogoStore.shared.image
            )
        case .screensaver:
            applyRemoteOverlayHeader(
                title: "Screensaver",
                systemImage: "sparkles.tv",
                thumbnail: ScreensaverStore.poster
            )
        case .livePoll:
            applyRemoteOverlayHeader(title: "Live Poll", systemImage: "chart.bar.fill")
        case .black, nil:
            liveHeader.configure(
                with: nil, thumbnail: nil, isOnline: true, showsLiveBadge: true
            )
        }
    }

    func applyRemoteOverlayHeader(
        title: String,
        systemImage: String,
        thumbnail: UIImage? = nil
    ) {
        liveHeader.configureOverlay(
            title: title,
            systemImage: systemImage,
            fillColor: UIColor(white: 0.12, alpha: 1),
            thumbnail: thumbnail,
            showsLiveBadge: true
        )
    }

    private func remoteWebTitle(_ id: String?) -> String {
        guard let id, let uuid = UUID(uuidString: id) else { return "Website" }
        return WebPageStore.shared.page(id: uuid)?.title ?? "Website"
    }

    private func remoteWebThumb(_ id: String?) -> UIImage? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return WebThumbnailStore.shared.image(for: uuid)
    }

    private func remotePDFTitle(_ id: String?) -> String {
        guard let id, let uuid = UUID(uuidString: id) else { return "PDF" }
        return PDFStore.shared.documents.first(where: { $0.id == uuid })?.title
            ?? "PDF"
    }

    private func remotePDFThumb(_ id: String?) -> UIImage? {
        guard let id, let uuid = UUID(uuidString: id) else { return nil }
        return PDFThumbnailStore.shared.image(for: uuid)
    }

    private func remoteSlideshowTitle(_ id: String?) -> String {
        guard let id, let uuid = UUID(uuidString: id) else { return "Slideshow" }
        return SlideshowStore.shared.slideshow(id: uuid)?.name ?? "Slideshow"
    }
}
