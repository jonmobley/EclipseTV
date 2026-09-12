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
            presentCountdownLive(item)
        case .slideshow:
            guard let itemId, let uuid = UUID(uuidString: itemId),
                  let show = SlideshowStore.shared.slideshow(id: uuid) else { return }
            // As the Show tap does: a tool left selected outranks the slides that
            // are about to go out.
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
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
                presentQuestPollLive()
            } else {
                startLivePoll(item)
            }
        case .black:
            if !isBlackSelected { toggleBlackLive() }
        }
    }

    /// Live stroke from the director snapshot instead of local program state.
    func isShowGridItemLiveRemotely(_ item: ShowGridItem) -> Bool {
        guard let snap = ShowLiveSession.shared.snapshot,
              let program = ShowProgram(snapshot: snap) else { return false }
        return program.matches(item)
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
        liveHeader.updatePlayback(PlaybackState())
    }

    /// Pushes current program to operators after a local go-live.
    func broadcastShowLiveSnapshotIfNeeded() {
        guard ShowLiveSession.shared.isDirector, let showId = openShowId else {
            return
        }
        ShowLiveSession.shared.broadcastSnapshot(makeShowLiveSnapshot(showId: showId))
    }

    func handleShowLiveSessionChanged() {
        if ShowLiveSession.shared.isRemoteOperator,
           let snap = ShowLiveSession.shared.snapshot {
            isLiveOutputLocked = snap.isLocked
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

    /// Program mirrored to operators, resolved through the same priority order the
    /// local grid paints with, so a follow phone cannot show a different tile live.
    func makeShowLiveSnapshot(showId: UUID) -> ShowLiveSnapshot {
        let program = ShowProgramResolver.resolve(
            showProgramState(includingPracticePoll: false)
        )
        return ShowLiveSnapshot(
            showId: showId,
            liveItemId: program?.itemId,
            liveKind: program?.kind,
            isBlackout: program?.kind == .black,
            isLocked: isLiveOutputLocked,
            directorName: UIDevice.current.name
        )
    }

    private func applyRemoteLiveHeaderContent(_ snap: ShowLiveSnapshot) {
        switch snap.liveKind {
        case .media:
            let item = snap.liveItemId.flatMap { id in
                store.items.first(where: { $0.id == id })
            }
            liveHeader.configure(
                with: item,
                thumbnail: item.flatMap { store.thumbnail(for: $0.id) },
                isOnline: true,
                usesRemoteVideoMonitor: item?.isVideo == true,
                showsLiveBadge: true
            )
        case .web:
            let page = snap.liveItemId
                .flatMap(UUID.init(uuidString:))
                .flatMap { WebPageStore.shared.page(id: $0) }
            let isVideo = page?.videoLink != nil
            applyRemoteOverlayHeader(
                title: remoteWebTitle(snap.liveItemId),
                systemImage: isVideo ? "play.rectangle.fill" : "safari",
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
            applyRemoteOverlayHeader(title: "Countdown", systemImage: "timer")
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

    private func applyRemoteOverlayHeader(
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
