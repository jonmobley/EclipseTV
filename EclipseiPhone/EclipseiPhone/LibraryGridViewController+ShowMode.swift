//
//  LibraryGridViewController+ShowMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Mode

extension LibraryGridViewController {

    /// Opens a Show from the Home menu or a home-grid tile.
    ///
    /// Switches Display Mode first when the Show belongs to the other layout.
    /// The prior Show is cleared *before* that flip so the Display Mode observer
    /// cannot rewrite or park a Show the user is leaving.
    func openLocalAlbum(id: UUID) {
        guard let album = LocalAlbumStore.shared.album(id: id) else { return }
        if album.orientation != ExternalOutputSettings.orientation {
            clearOpenShowForModeSwitch()
            ExternalOutputSettings.orientation = album.orientation
            // Observer runs `applyLayoutMode()`; do not reload again here.
        }
        enterShowMode(album)
    }

    /// Drops Show mode state before a Display Mode flip that opens another Show.
    ///
    /// Reveals Home without rewriting the hidden Show page.
    private func clearOpenShowForModeSwitch() {
        showAwaitingReturnId = nil
        guard openShowId != nil else { return }
        if isArranging {
            cancelArranging()
        }
        if isSelecting {
            cancelSelecting()
        }
        stopHomeCameraPreviewIfNeeded()
        openShowId = nil
        onOpenShowChanged?(nil)
        enforceHomeLiveHeroTeardownIfNeeded()
        stopQuestPollStatusPolling()
        updateVisibleLibraryPage()
        applyShowPageLayout()
        reloadLibraryGrid()
        syncShowLiveSession()
    }

    /// Leaves Show mode and restores the Recent Shows ribbon.
    func closeOpenShow() {
        guard openShowId != nil else { return }
        showAwaitingReturnId = nil
        if isArranging {
            cancelArranging()
        }
        if isSelecting {
            cancelSelecting()
        }
        // Freeze the tile on a still while it's still on screen to grab from.
        stopHomeCameraPreviewIfNeeded()
        openShowId = nil
        // Header first — otherwise Home chrome lags and the grid can briefly keep
        // Show tool cells (Screensaver / Background) after the title already says Home.
        onOpenShowChanged?(nil)
        // Drop Show-only live chrome so Home never keeps a Screensaver / Background
        // hero over the marketing carousel (AirPlay can keep playing).
        enforceHomeLiveHeroTeardownIfNeeded()
        stopQuestPollStatusPolling()
        updateVisibleLibraryPage()
        applyShowPageLayout()
        reloadLibraryGrid()
        scrollGridToTop()
        updateEmptyState()
        updateHeroCollapse()
        refreshMusicSwipeHintVisibility()
        syncShowLiveSession()
    }

    /// Closes Show mode when the open Show is missing or in another Display Mode, and
    /// reopens the Show a previous such close set aside once it is valid again.
    ///
    /// - Parameter adoptingCurrentDisplayMode: When true (user changed Display Mode
    ///   in Settings), move the *currently open* Show into the new mode. Cross-mode
    ///   Show opens clear `openShowId` first so this never rewrites a Show the user
    ///   is leaving.
    func validateOpenShow(adoptingCurrentDisplayMode: Bool = false) {
        guard let id = openShowId else {
            reopenShowAwaitingReturn()
            return
        }
        guard let album = LocalAlbumStore.shared.album(id: id) else {
            closeOpenShow()
            return
        }
        if album.orientation != ExternalOutputSettings.orientation {
            if adoptingCurrentDisplayMode {
                LocalAlbumStore.shared.setOrientation(
                    id: id,
                    orientation: ExternalOutputSettings.orientation
                )
                guard let updated = LocalAlbumStore.shared.album(id: id) else {
                    closeOpenShow()
                    return
                }
                onOpenShowChanged?(updated)
                return
            }
            closeOpenShow()
            showAwaitingReturnId = id
            return
        }
        onOpenShowChanged?(album)
    }

    /// Reopens the Show that a Display Mode change closed, once that mode is active
    /// again. Leaving Show mode deliberately (Home, Delete) clears the pending Show, so
    /// this only ever undoes a close the user did not ask for.
    private func reopenShowAwaitingReturn() {
        guard let id = showAwaitingReturnId,
              let album = LocalAlbumStore.shared.album(id: id),
              album.orientation == ExternalOutputSettings.orientation else { return }
        showAwaitingReturnId = nil
        enterShowMode(album)
    }

    /// Confirms and deletes the open Show, then returns Home.
    func confirmDeleteOpenShow() {
        guard let show = openShow else { return }
        let alert = UIAlertController(
            title: "Delete Show?",
            message: "“\(show.name)” is removed from Home. Its images and videos stay on this iPhone and any linked EclipseTV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            LocalAlbumStore.shared.delete(id: show.id)
            self?.closeOpenShow()
        })
        present(alert, animated: true)
    }

    /// Returns the grid to the top when the section contents change wholesale.
    ///
    /// Home and a Show have unrelated content heights, so carrying the old offset across
    /// the transition dropped the user into the middle of the new content — or past the
    /// end of it, staring at blank space.
    private func scrollGridToTop() {
        let top = -collectionView.adjustedContentInset.top
        guard collectionView.contentOffset.y != top else { return }
        collectionView.setContentOffset(CGPoint(x: 0, y: top), animated: false)
    }

    // MARK: - Enter

    private func enterShowMode(_ album: LocalAlbum) {
        guard album.orientation == ExternalOutputSettings.orientation else { return }
        showAwaitingReturnId = nil
        if isArranging {
            cancelArranging()
        }
        if isSelecting {
            cancelSelecting()
        }
        LocalAlbumStore.shared.touchRecentlyOpened(id: album.id)
        let wasShowMode = isShowMode
        openShowId = album.id
        updateVisibleLibraryPage()
        applyShowPageLayout()
        if !wasShowMode {
            updateHeroVisibility()
        }
        reloadLibraryGrid()
        scrollGridToTop()
        updateEmptyState()
        // Show website cards exist for quick access — warm them as soon as the Show opens.
        WarmWebSessionPool.shared.warmSoon(openShowWebPages)
        // Always refresh — switching Shows may park prior live into the foreign mini.
        refreshLiveHeader()
        updateHeroCollapse()
        syncShowLiveSession()
        if !wasShowMode {
            // The Camera tile only exists once the new sections are laid out, and
            // an already-running session won't fire a start notification to retry on.
            collectionView.layoutIfNeeded()
            warmHomeCameraPreview()
        }
        onOpenShowChanged?(album)
    }

    // MARK: - Show Grid Cells / Actions

    func numberOfShowModeItems() -> Int {
        openShowGridItems.count
    }

    /// Resolves one Show surface id to a grid row, or nil if that member is gone.
    func showGridItem(forSurfaceId id: String) -> ShowGridItem? {
        switch id {
        case ShowToolToken.screensaver: return .screensaver
        case ShowToolToken.logo: return .logo
        case ShowToolToken.camera: return .camera
        default:
            if let uuid = ShowLivePollToken.livePollId(from: id) {
                if let item = LivePollStore.shared.poll(id: uuid),
                   item.showId == openShowId {
                    return .livePoll(item)
                }
                return .unresolved(id: id)
            }
            if let uuid = ShowSlideshowToken.slideshowId(from: id) {
                if let show = SlideshowStore.shared.slideshow(id: uuid),
                   show.showId == openShowId {
                    return .slideshow(show)
                }
                return .unresolved(id: id)
            }
            if let uuid = ShowCountdownToken.countdownId(from: id) {
                if let item = CountdownStore.shared.countdown(id: uuid),
                   item.showId == openShowId {
                    return .countdown(item)
                }
                return .unresolved(id: id)
            }
            if let item = store.items.first(where: { $0.id == id }) {
                return .media(item)
            }
            if let imported = ImportedMediaStore.shared.record(id: id) {
                return .media(imported.asLibraryItem)
            }
            if let capture = CaptureStore.shared.record(id: id) {
                return .media(capture.asLibraryItem)
            }
            guard let uuid = UUID(uuidString: id) else {
                return .unresolved(id: id)
            }
            if let page = WebPageStore.shared.page(id: uuid) {
                return .website(page)
            }
            if let doc = PDFStore.shared.documents.first(where: { $0.id == uuid }) {
                return .pdf(doc)
            }
            return .unresolved(id: id)
        }
    }

    func configureShowModeCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return }
        let gridItem = items[indexPath.item]
        let live = isShowGridItemLive(gridItem)
        switch gridItem {
        case .slideshow(let show):
            let cover = show.resolvedCoverId.flatMap { store.thumbnail(for: $0) }
            cell.configureSpecial(
                title: show.name,
                systemImage: "rectangle.stack.fill",
                thumbnail: cover,
                fillColor: .darkGray,
                isLive: live,
                isLocked: isLiveOutputLocked,
                thumbnailContentMode: show.isFill
                    ? .scaleAspectFill
                    : .scaleAspectFit,
                typeIcon: .slideshow
            )
            cell.setMoreMenu(
                (isArranging || isSelecting) ? nil : slideshowContextMenu(show)
            )
        case .screensaver:
            cell.configureSpecial(
                title: "Screensaver",
                systemImage: ScreensaverStore.isVideo ? "play.fill" : "photo.fill",
                thumbnail: ScreensaverStore.poster,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: live,
                isLocked: isLiveOutputLocked,
                thumbnailContentMode: .scaleAspectFill,
                typeIcon: .media(isVideo: ScreensaverStore.isVideo)
            )
            cell.setMoreMenu(
                (isArranging || isSelecting)
                    ? nil
                    : toolContextMenu(token: ShowToolToken.screensaver)
            )
        case .logo:
            cell.configureSpecial(
                title: "Background",
                systemImage: "photo.fill",
                thumbnail: LogoStore.shared.image,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: live,
                isLocked: isLiveOutputLocked,
                thumbnailContentMode: .scaleAspectFill,
                typeIcon: .photo
            )
            cell.setMoreMenu(
                (isArranging || isSelecting)
                    ? nil
                    : toolContextMenu(token: ShowToolToken.logo)
            )
        case .camera:
            cell.configureCamera(
                isLive: live,
                lastFrame: CameraManager.shared.lastFrame,
                parkedStill: ShowLiveSession.shared.isRemoteOperator
                    ? nil
                    : ExternalDisplayManager.shared.cameraTileParkedStillImage,
                warmPreview: !ShowLiveSession.shared.isRemoteOperator
                    && !isCameraControlPresented
                    && !homeCameraWarmPreviewSuspended,
                isLocked: isLiveOutputLocked
            )
            cell.setMoreMenu(
                (isArranging || isSelecting)
                    ? nil
                    : toolContextMenu(token: ShowToolToken.camera)
            )
        case .livePoll(let item):
            configureLivePollTile(cell, item: item, isLive: live)
            cell.setMoreMenu(
                (isArranging || isSelecting) ? nil : livePollContextMenu(item)
            )
        case .countdown(let item):
            configureCountdownTile(cell, item: item, isLive: live)
            cell.setMoreMenu(
                (isArranging || isSelecting) ? nil : countdownContextMenu(item)
            )
        case .media(let item):
            let resume = VideoResumeStore.shared
            let parked = resume.frame(for: item.id)
            cell.configure(
                with: item,
                thumbnail: parked ?? store.thumbnail(for: item.id),
                isLive: live,
                isLocked: isLiveOutputLocked
            )
            if isArranging || isSelecting {
                cell.clearMoreMenu()
                cell.clearRewind()
            } else {
                if let album = openShow {
                    cell.setMoreMenu(mediaContextMenu(item, in: album))
                }
                applyVideoRewind(to: cell, item: item, isLive: live)
            }
        case .website(let page):
            cell.configureSpecial(
                title: page.title,
                systemImage: "safari",
                thumbnail: WebThumbnailStore.shared.image(for: page.id),
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: live,
                isLocked: isLiveOutputLocked,
                typeIcon: .website
            )
            if isArranging || isSelecting {
                cell.clearMoreMenu()
            } else if let album = openShow {
                cell.setMoreMenu(websiteContextMenu(page, in: album))
            }
        case .pdf(let doc):
            cell.configureSpecial(
                title: doc.title,
                systemImage: "doc.richtext",
                thumbnail: PDFThumbnailStore.shared.image(for: doc.id),
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: live,
                isLocked: isLiveOutputLocked,
                titleNumberOfLines: 1,
                typeIcon: .pdf
            )
            if isArranging || isSelecting {
                cell.clearMoreMenu()
            } else if let album = openShow {
                cell.setMoreMenu(pdfContextMenu(doc, in: album))
            }
        case .unresolved:
            cell.configureSpecial(
                title: "Syncing…",
                systemImage: "icloud.and.arrow.down",
                thumbnail: nil,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: false,
                outlined: true,
                typeIcon: nil
            )
            cell.clearMoreMenu()
        case .add:
            cell.configureActionTile(
                title: "",
                systemImage: "plus",
                menu: addMenuProvider?()
            )
            cell.clearMoreMenu()
        }
    }

    func handleShowModeTap(at indexPath: IndexPath) {
        guard !isArranging, !isSelecting else { return }
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return }
        switch items[indexPath.item] {
        case .slideshow(let show):
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            presentSlideshow(show)
        case .screensaver:
            if isLiveOutputLocked {
                presentScreensaverPhonePreview()
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            presentScreensaverLive()
        case .logo:
            if isLiveOutputLocked {
                presentLogoPhonePreview()
                return
            }
            isBlackSelected = false
            isScreensaverSelected = false
            presentLogoLive()
        case .camera:
            if isLiveOutputLocked || !hasLiveOutputDestination {
                onPresentCamera?()
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            presentCameraLiveOnOutput()
        case .livePoll(let item):
            isLogoSelected = false
            isScreensaverSelected = false
            selectLivePoll(item)
        case .countdown(let item):
            isLogoSelected = false
            isScreensaverSelected = false
            beginCountdown(item)
        case .media(let item):
            if isLiveOutputLocked {
                presentLocalPreview(for: item, in: openShowItems)
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            SlideshowPlaybackController.shared.stop()
            presentMedia(item)
        case .website(let page):
            if isLiveOutputLocked || !hasLiveOutputDestination {
                presentWebPage(page)
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            presentWebPageLive(page)
        case .pdf(let doc):
            if isLiveOutputLocked || !hasLiveOutputDestination {
                presentPDF(doc)
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            presentPDFLive(doc)
        case .unresolved(let id):
            requestUnresolvedDownloadIfNeeded(id: id)
        case .add:
            break
        }
    }

    /// Presents the slideshow on AirPlay / Multipeer, or locally when disconnected.
    ///
    /// After a manual mid-show leave, offers Resume (last slide) or Restart.
    func presentSlideshow(_ slideshow: Slideshow) {
        guard !slideshow.itemIds.isEmpty else {
            presentSlideshowEditor(slideshow.id)
            return
        }
        guard !blockLiveChangeIfLocked() else { return }
        if sendShowLiveSelectIfOperator(.slideshow, itemId: slideshow.id.uuidString) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            return
        }
        guard hasLiveOutputDestination else {
            if let first = slideshow.itemIds.first {
                if presentShowPreviewGallery(startingAt: first) { return }
                if let item = store.items.first(where: { $0.id == first }) {
                    presentLocalPreview(for: item, in: openShowItems)
                }
            }
            return
        }
        let playback = SlideshowPlaybackController.shared
        if playback.isLive(slideshowId: slideshow.id) {
            // Already on this show — leave it alone.
            return
        }
        if let resumeAt = playback.resumeIndex(for: slideshow), resumeAt > 0 {
            promptResumeOrRestartSlideshow(slideshow, resumeAt: resumeAt)
            return
        }
        startSlideshow(slideshow, startingAt: 0)
    }

    /// Resume / Restart after the user left mid-show following a manual advance.
    private func promptResumeOrRestartSlideshow(_ slideshow: Slideshow, resumeAt: Int) {
        let alert = UIAlertController(
            title: slideshow.name,
            message: "Continue from slide \(resumeAt + 1), or start over?",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Resume", style: .default) { [weak self] _ in
            self?.startSlideshow(slideshow, startingAt: resumeAt)
        })
        alert.addAction(UIAlertAction(title: "Restart", style: .default) { [weak self] _ in
            SlideshowPlaybackController.shared.clearResume(for: slideshow.id)
            self?.startSlideshow(slideshow, startingAt: 0)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    private func startSlideshow(_ slideshow: Slideshow, startingAt: Int) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SlideshowPlaybackController.shared.play(
            slideshow,
            connectionManager: connectionManager,
            startingAt: startingAt
        )
        collectionView.reloadData()
        refreshLiveHeader()
    }

    /// Opens the slideshow editor (preferences + reorder).
    func presentSlideshowEditor(_ slideshowId: UUID) {
        let detail = SlideshowDetailViewController(slideshowId: slideshowId)
        let nav = UINavigationController(rootViewController: detail)
        nav.modalPresentationStyle = .formSheet
        let close = UIBarButtonItem(
            systemItem: .close,
            primaryAction: UIAction { [weak nav] _ in
                nav?.dismiss(animated: true)
            }
        )
        detail.navigationItem.leftBarButtonItem = close
        present(nav, animated: true)
    }

    // MARK: - Private

    private func slideshowContextMenu(_ show: Slideshow) -> UIMenu {
        let edit = UIAction(
            title: "Edit",
            image: UIImage(systemName: "slider.horizontal.3")
        ) { [weak self] _ in
            self?.presentSlideshowEditor(show.id)
        }
        let rename = UIAction(
            title: "Rename",
            image: UIImage(systemName: "pencil")
        ) { [weak self] _ in
            self?.promptRenameSlideshow(show)
        }
        let delete = UIAction(
            title: "Delete Slideshow",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeleteSlideshow(show)
        }
        return UIMenu(children: [edit, screenFitMenu(for: show), rename, arrangeAction(), delete])
    }

    private func mediaContextMenu(_ item: LibraryItemDTO, in album: LocalAlbum) -> UIMenu {
        let items = openShowItems
        let isCover = album.resolvedCoverId == item.id
        let cover = UIAction(
            title: isCover ? "Show Cover" : "Set as Show Cover",
            image: UIImage(systemName: isCover ? "star.fill" : "star"),
            attributes: isCover ? [.disabled] : []
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.setCover(itemId: item.id, albumId: id)
        }
        let remove = UIAction(
            title: "Remove",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.remove(itemId: item.id, fromAlbumId: id)
        }
        let arrange = arrangeAction()
        var children: [UIMenuElement] = [
            UIAction(
                title: "Preview",
                image: UIImage(systemName: "eye")
            ) { [weak self] _ in
                self?.presentLocalPreview(for: item, in: items)
            },
            titleAction(for: item)
        ]
        if item.isVideo {
            children.append(contentsOf: videoOptionActions(for: item))
        } else {
            children.append(screenFitMenu(for: item))
            children.append(noteAction(for: item))
        }
        if let capture = CaptureStore.shared.record(id: item.id),
           LocalMediaStore.shared.hasMedia(
            forId: capture.libraryFileName,
            mode: capture.orientation.libraryMode
           ) {
            let evict = UIAction(
                title: "Remove Download",
                image: UIImage(systemName: "iphone.and.arrow.forward")
            ) { _ in
                EclipseSyncController.shared.backend.removeLocalDownload(id: capture.id)
            }
            children.append(evict)
        }
        children.append(contentsOf: [cover, arrange, selectAction(seedId: item.id), remove])
        return UIMenu(children: children)
    }

    private func websiteContextMenu(_ page: WebPage, in album: LocalAlbum) -> UIMenu {
        let preview = UIAction(
            title: "Preview",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.presentWebPage(page)
        }
        let rest = memberContextMenu(itemId: page.id.uuidString, in: album)
        return UIMenu(children: [preview] + rest.children)
    }

    /// Cover / Arrange / Remove for a Show member (media, website, or PDF id).
    /// - Parameter extras: Appended after Remove (PDF adds a store-level Delete).
    func memberContextMenu(
        itemId: String,
        in album: LocalAlbum,
        extras: [UIMenuElement] = []
    ) -> UIMenu {
        let isCover = album.resolvedCoverId == itemId
        let cover = UIAction(
            title: isCover ? "Show Cover" : "Set as Show Cover",
            image: UIImage(systemName: isCover ? "star.fill" : "star"),
            attributes: isCover ? [.disabled] : []
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.setCover(itemId: itemId, albumId: id)
        }
        let remove = UIAction(
            title: "Remove",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.remove(itemId: itemId, fromAlbumId: id)
        }
        return UIMenu(
            children: [cover, arrangeAction(), selectAction(seedId: itemId), remove] + extras
        )
    }

    private func toolContextMenu(token: String) -> UIMenu {
        var children: [UIMenuElement] = []
        switch token {
        case ShowToolToken.logo:
            children.append(UIAction(
                title: "Preview",
                image: UIImage(systemName: "eye")
            ) { [weak self] _ in
                self?.presentLogoPhonePreview()
            })
            children.append(UIAction(
                title: "Replace",
                image: UIImage(systemName: "photo")
            ) { [weak self] _ in
                self?.onChooseLogo?()
            })
            if LogoStore.shared.hasCustomImage {
                children.append(UIAction(
                    title: "Reset to Default",
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { _ in
                    LogoStore.shared.clear()
                })
            }
        case ShowToolToken.camera:
            children.append(UIAction(
                title: "Open Controller",
                image: UIImage(systemName: "camera.viewfinder")
            ) { [weak self] _ in
                self?.onPresentCamera?()
            })
        case ShowToolToken.screensaver:
            children.append(UIAction(
                title: "Preview",
                image: UIImage(systemName: "eye")
            ) { [weak self] _ in
                self?.presentScreensaverPhonePreview()
            })
            children.append(UIAction(
                title: "Replace",
                image: UIImage(systemName: "photo.on.rectangle")
            ) { [weak self] _ in
                self?.onChooseScreensaver?()
            })
            if ScreensaverStore.hasCustomMedia {
                children.append(UIAction(
                    title: "Reset to Default",
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { _ in
                    ScreensaverStore.shared.clear()
                })
            }
        default:
            break
        }
        children.append(arrangeAction())
        children.append(selectAction(seedId: token))
        let remove = UIAction(
            title: "Remove",
            image: UIImage(systemName: "eye.slash"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.hideTool(token, albumId: id)
        }
        children.append(remove)
        return UIMenu(children: children)
    }

    func arrangeAction() -> UIAction {
        UIAction(
            title: "Arrange",
            image: UIImage(systemName: "arrow.up.arrow.down"),
            attributes: openShowMovableCount < 2 ? [.disabled] : []
        ) { [weak self] _ in
            self?.beginArranging()
        }
    }

    func selectAction(seedId: String) -> UIAction {
        UIAction(
            title: "Select…",
            image: UIImage(systemName: "checkmark.circle")
        ) { [weak self] _ in
            self?.beginSelecting(seedId: seedId)
        }
    }

    private func promptRenameSlideshow(_ show: Slideshow) {
        let alert = UIAlertController(
            title: "Rename Slideshow", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = show.name
            field.autocapitalizationType = .words
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            try? SlideshowStore.shared.rename(id: show.id, to: name)
        })
        present(alert, animated: true)
    }

    private func confirmDeleteSlideshow(_ show: Slideshow) {
        let alert = UIAlertController(
            title: "Delete Slideshow?",
            message: "“\(show.name)” is removed. Its images stay in your library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            if SlideshowPlaybackController.shared.isLive(slideshowId: show.id) {
                SlideshowPlaybackController.shared.stop()
            }
            SlideshowStore.shared.delete(id: show.id)
        })
        present(alert, animated: true)
    }

    /// Shows a non-live Rewind control when a mid-play leave is parked for `item`.
    func applyVideoRewind(
        to cell: LibraryThumbnailCell,
        item: LibraryItemDTO,
        isLive: Bool
    ) {
        guard item.isVideo,
              !isLive,
              VideoResumeStore.shared.hasResume(for: item.id)
        else {
            cell.clearRewind()
            return
        }
        let itemId = item.id
        cell.setRewindHandler { [weak self] in
            VideoResumeStore.shared.clear(for: itemId)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            self?.reloadGridIfSafe()
        }
    }
}
