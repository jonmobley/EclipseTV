//
//  LibraryGridViewController+HomeGrid.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Home Grid Data Source & Actions

extension LibraryGridViewController: UICollectionViewDataSource,
                                     UICollectionViewDelegate {

    func numberOfSections(in collectionView: UICollectionView) -> Int {
        pageSections(for: collectionView).count
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        guard let homeSection = homeSection(at: section, in: collectionView) else {
            return 0
        }
        switch homeSection {
        case .hero: return isHomePage(collectionView) ? 1 : 0
        case .tools: return 0
        case .slideshowRibbon: return liveSlideshowRibbonItemCount()
        case .shows:
            return isHomePage(collectionView)
                ? showRibbonItems.count
                : numberOfShowModeItems()
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        // Home is its own collection view — it can never dequeue a Show tile.
        if isHomePage(collectionView) {
            switch homeSection(at: indexPath.section, in: collectionView) {
            case .hero:
                return dequeueHomeHeroCell(in: collectionView, at: indexPath)
            case .shows:
                if homeItem(at: indexPath) == .createShow {
                    return dequeueHomeCreateShowCell(in: collectionView, at: indexPath)
                }
                return dequeueHomeShowTileCell(in: collectionView, at: indexPath)
            case .tools, .slideshowRibbon, .none:
                return UICollectionViewCell()
            }
        }

        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LibraryThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as? LibraryThumbnailCell else {
            return UICollectionViewCell()
        }
        if isDockedSlideshowRibbon(collectionView) {
            configureLiveSlideshowRibbonCell(cell, at: indexPath)
            return cell
        }
        // Every exit path, so a recycled cell never keeps a stale wiggle or dim.
        defer {
            applyArrangeAppearance(to: cell, at: indexPath)
            applySelectAppearance(to: cell, at: indexPath)
        }

        guard let section = homeSection(at: indexPath.section, in: collectionView) else {
            return cell
        }
        switch section {
        case .hero, .tools:
            break
        case .slideshowRibbon:
            configureLiveSlideshowRibbonCell(cell, at: indexPath)
        case .shows:
            configureShowModeCell(cell, at: indexPath)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        guard let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier,
            for: indexPath
        ) as? HomeSectionHeaderView else {
            return UICollectionReusableView()
        }
        switch homeSection(at: indexPath.section, in: collectionView) {
        case .hero:
            header.configure(title: "")
        case .tools:
            header.configure(title: "")
        case .slideshowRibbon:
            header.configure(title: "")
        case .shows:
            if isHomePage(collectionView) {
                header.configure(
                    title: "Recent",
                    trailingTitle: "See All",
                    trailingHandler: { [weak self] in
                        self?.presentAllShows()
                    },
                    actions: homeRecentFilterActions()
                )
            } else {
                header.configure(title: "")
            }
        case .none:
            header.configure(title: "")
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard !isArranging else { return }
        if isSelecting {
            if homeSection(at: indexPath.section, in: collectionView) == .shows,
               !isHomePage(collectionView) {
                handleSelectModeTap(at: indexPath)
            }
            return
        }
        switch homeSection(at: indexPath.section, in: collectionView) {
        case .hero:
            break
        case .slideshowRibbon:
            handleLiveSlideshowRibbonTap(at: indexPath)
        case .shows where !isHomePage(collectionView):
            handleShowModeTap(at: indexPath)
        default:
            guard let item = homeItem(at: indexPath) else { return }
            handleTap(item)
        }
    }

    func scrollViewDidEndDragging(
        _ scrollView: UIScrollView,
        willDecelerate decelerate: Bool
    ) {
        guard scrollView === collectionView else { return }
        updateHomeVerticalScrollPolicy()
        if !decelerate {
            refreshVisibleThumbnailPins()
        }
    }

    func scrollViewDidEndDecelerating(_ scrollView: UIScrollView) {
        guard scrollView === collectionView else { return }
        updateHomeVerticalScrollPolicy()
        refreshVisibleThumbnailPins()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        willDisplay cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        refreshVisibleThumbnailPins()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        didEndDisplaying cell: UICollectionViewCell,
        forItemAt indexPath: IndexPath
    ) {
        refreshVisibleThumbnailPins()
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isArranging, !isSelecting else { return nil }
        switch homeSection(at: indexPath.section, in: collectionView) {
        case .hero, .slideshowRibbon:
            return nil
        case .shows where !isHomePage(collectionView):
            // Show tiles: long-press enters arrange; ⋯ hosts Preview / Cover / Remove.
            return nil
        default:
            guard let item = homeItem(at: indexPath) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self] _ in
                self?.contextMenu(for: item)
            }
        }
    }

    // MARK: - Hero

    private func dequeueHomeHeroCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeHeroCarouselCell.reuseIdentifier,
            for: indexPath
        ) as? HomeHeroCarouselCell else {
            return UICollectionViewCell()
        }
        cell.reload()
        return cell
    }

    // MARK: - Home Show Tiles

    /// Same soft Add chrome as an empty Show (`configureActionTile`).
    private func dequeueHomeCreateShowCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LibraryThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as? LibraryThumbnailCell else {
            return UICollectionViewCell()
        }
        cell.configureActionTile(title: "New Show", systemImage: "plus")
        return cell
    }

    private func dequeueHomeShowTileCell(
        in collectionView: UICollectionView,
        at indexPath: IndexPath
    ) -> UICollectionViewCell {
        guard let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: HomeShowTileCell.reuseIdentifier,
            for: indexPath
        ) as? HomeShowTileCell else {
            return UICollectionViewCell()
        }
        guard case .show(let show) = homeItem(at: indexPath) else { return cell }
        let coverId = show.resolvedCoverId
        let thumb = coverId.flatMap { id -> UIImage? in
            if let media = store.thumbnail(for: id) { return media }
            guard let uuid = UUID(uuidString: id) else { return nil }
            return WebThumbnailStore.shared.image(for: uuid)
                ?? PDFThumbnailStore.shared.image(for: uuid)
        }
        let mgr = ExternalDisplayManager.shared
        let isLiveShow = (
            show.itemIds.contains(where: { $0 == store.currentId })
                && !mgr.isOverlayLive
        ) || (
            mgr.isWebLive
                && mgr.liveWebPageId.map { show.itemIds.contains($0.uuidString) } == true
        )
        let live = isLiveShow && !isBlackSelected && !isLogoSelected
            && !isScreensaverSelected
        cell.configureShow(
            showId: show.id,
            title: show.name,
            subtitle: show.homeRecentSubtitle,
            thumbnail: thumb,
            isLive: live,
            moreMenu: contextMenu(for: .show(show))
        )
        return cell
    }

    /// Presents the full Shows list (both Display Modes).
    func presentAllShows() {
        let list = AllShowsViewController()
        list.onOpenShow = { [weak self] id in
            self?.openLocalAlbum(id: id)
        }
        list.onCreateShow = { [weak self] in
            self?.onCreateShow?()
        }
        // Page sheets often skip the presenter's viewWillAppear on dismiss — if the
        // user left a Show with Live Screensaver still up, Close/swipe must clear it.
        list.onDismissWithoutOpening = { [weak self] in
            self?.enforceHomeLiveHeroTeardownIfNeeded()
        }
        let nav = UINavigationController(rootViewController: list)
        nav.modalPresentationStyle = .pageSheet
        present(nav, animated: true)
    }

    // MARK: - Cell Config

    private func configure(_ cell: LibraryThumbnailCell, with item: HomeGridItem) {
        switch item {
        case .logo:
            cell.configureSpecial(
                title: "Background",
                systemImage: "photo.fill",
                thumbnail: LogoStore.shared.image,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: isLogoSelected && !ExternalDisplayManager.shared.isOverlayLive,
                isLocked: isLiveOutputLocked,
                thumbnailContentMode: .scaleAspectFill,
                typeIcon: .photo
            )
            cell.setMoreMenu(contextMenu(for: .logo))
        case .screensaver:
            cell.configureSpecial(
                title: "Screensaver",
                systemImage: ScreensaverStore.isVideo ? "play.fill" : "photo.fill",
                thumbnail: ScreensaverStore.poster,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: isScreensaverSelected
                    && !ExternalDisplayManager.shared.isOverlayLive,
                isLocked: isLiveOutputLocked,
                thumbnailContentMode: .scaleAspectFill,
                typeIcon: .media(isVideo: ScreensaverStore.isVideo)
            )
        case .camera:
            cell.configureCamera(
                isLive: ExternalDisplayManager.shared.isCameraTileLive,
                lastFrame: CameraManager.shared.lastFrame,
                parkedStill: ExternalDisplayManager.shared.cameraTileParkedStillImage,
                warmPreview: !isCameraControlPresented && !homeCameraWarmPreviewSuspended,
                isLocked: isLiveOutputLocked
            )
        case .createShow:
            cell.configureActionTile(title: "New Show", systemImage: "plus")
        case .addShowMedia:
            cell.configureActionTile(
                title: "",
                systemImage: "plus",
                menu: addMenuProvider?()
            )
        case .show(let show):
            let coverId = show.resolvedCoverId
            let thumb = coverId.flatMap { id -> UIImage? in
                if let media = store.thumbnail(for: id) { return media }
                guard let uuid = UUID(uuidString: id) else { return nil }
                return WebThumbnailStore.shared.image(for: uuid)
            }
            let mgr = ExternalDisplayManager.shared
            let isLiveShow = (
                show.itemIds.contains(where: { $0 == store.currentId })
                    && !mgr.isOverlayLive
            ) || (
                mgr.isWebLive
                    && mgr.liveWebPageId.map { show.itemIds.contains($0.uuidString) } == true
            )
            let live = isLiveShow && !isBlackSelected && !isLogoSelected
                && !isScreensaverSelected
            cell.configureSpecial(
                title: show.name,
                systemImage: "rectangle.stack.fill",
                thumbnail: thumb,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: live
            )
        }
    }

    // MARK: - Taps

    private func handleTap(_ item: HomeGridItem) {
        switch item {
        case .logo:
            if isLiveOutputLocked {
                presentLogoPhonePreview()
                return
            }
            isBlackSelected = false
            isScreensaverSelected = false
            presentLogoLive()
        case .screensaver:
            if isLiveOutputLocked {
                presentScreensaverPhonePreview()
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            presentScreensaverLive()
        case .camera:
            if isLiveOutputLocked || !hasLiveOutputDestination {
                onPresentCamera?()
                return
            }
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            presentCameraLiveOnOutput()
        case .createShow:
            onCreateShow?()
        case .addShowMedia:
            // Menu is hosted on the tile (`showsMenuAsPrimaryAction`).
            break
        case .show(let show):
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
            openLocalAlbum(id: show.id)
        }
    }

    /// Toggles a solid black frame on AirPlay (header Blackout control).
    ///
    /// On: blanks the display without clearing Show selection. Off: restores what
    /// was live before. Avoids `updateCurrentId` / full `reloadData` — those were
    /// stacking a second present + grid rebuild and freezing the UI for seconds.
    func toggleBlackLive() {
        guard !blockLiveChangeIfLocked() else { return }
        if isBlackSelected {
            isBlackSelected = false
            ExternalDisplayManager.shared.endBlackout()
        } else {
            SlideshowPlaybackController.shared.stop()
            // Snapshot before flipping the flag — `currentSourceProvider` prefers black.
            ExternalDisplayManager.shared.beginBlackout()
            isBlackSelected = true
            announceAirPlayOverlayIfLinked()
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        refreshLiveHeader()
        let visible = collectionView.indexPathsForVisibleItems
        if !visible.isEmpty {
            collectionView.reconfigureItems(at: visible)
        }
    }

    /// Presents a solid black frame on AirPlay (header Black control).
    func presentBlackLive() {
        guard !isBlackSelected else { return }
        toggleBlackLive()
    }

    /// Marks Background live and presents the Background still on AirPlay.
    func presentLogoLive() {
        guard !blockLiveChangeIfLocked() else { return }
        guard let source = LogoStore.shared.presentationSource else {
            onChooseLogo?()
            return
        }
        SlideshowPlaybackController.shared.stop()
        isBlackSelected = false
        isLogoSelected = true
        isScreensaverSelected = false
        store.updateCurrentId(nil)
        ExternalDisplayManager.shared.present(source)
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Marks Screensaver live and presents the looping video on AirPlay.
    func presentScreensaverLive() {
        guard !blockLiveChangeIfLocked() else { return }
        guard let source = ScreensaverStore.presentationSource else { return }
        SlideshowPlaybackController.shared.stop()
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = true
        store.updateCurrentId(nil)
        ExternalDisplayManager.shared.present(source)
        announceAirPlayOverlayIfLinked()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Marks Screensaver live when AirPlay / Practice is already showing it as fallback.
    func syncScreensaverFallbackLiveSelection() {
        let mgr = ExternalDisplayManager.shared
        isScreensaverSelected = LiveOutputRouting.isScreensaverFallbackLive(
            hasOutputDestination: hasLiveOutputDestination,
            isOverlayLive: mgr.isOverlayLive,
            isJoinedLive: mgr.isJoinedLive,
            isBlackSelected: isBlackSelected,
            isLogoSelected: isLogoSelected,
            hasLibraryLiveItem: store.currentId != nil,
            hasLiveSlideshow: SlideshowPlaybackController.shared.activeSlideshowId != nil
        )
    }

    /// Opens the phone browser for a saved website (⋯ Preview).
    ///
    /// Marks it live when a destination exists and output is unlocked; otherwise this
    /// is on-device Preview without a red live stroke.
    ///
    /// A second browser must never open on top of the first — that left the loser with
    /// an empty stage and leaked the warm web view. If one is already up, navigate it
    /// like a normal browser load so Back still works and AirPlay follows.
    func presentWebPage(_ page: WebPage) {
        let markLive = hasLiveOutputDestination && !isLiveOutputLocked
        if let open = openController(ofType: WebRemoteViewController.self) {
            if markLive {
                SlideshowPlaybackController.shared.stop()
                ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
                announceAirPlayOverlayIfLinked()
            }
            open.loadBrowserURL(page.url, pageId: page.id)
            reloadLibraryGrid()
            refreshLiveHeader()
            return
        }
        if markLive {
            SlideshowPlaybackController.shared.stop()
        }
        WarmWebSessionPool.shared.warmIfNeeded(for: page)
        // Park any in-hero preview before adopt so Auto Layout pins don't stick.
        liveHeader.clearWebPreview(parking: true)
        if markLive {
            ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
            announceAirPlayOverlayIfLinked()
        }
        let remote = WebRemoteViewController(page: page)
        // Landscape Display Mode rotates the browser; a plain nav controller would not.
        let nav = DisplayModeNavigationController(rootViewController: remote)
        nav.modalPresentationStyle = .fullScreen
        if remote.usesOverlayBrowserChrome {
            nav.setNavigationBarHidden(true, animated: false)
        }
        present(nav, animated: true)
        reloadLibraryGrid()
        // After adopt: hero shows a static thumb (live preview is in the browser).
        refreshLiveHeader()
    }

    /// Opens the phone PDF reader (⋯ Preview).
    ///
    /// One viewer at a time, checked before the side effects: a second open would
    /// restart the AirPlay overlay for a viewer UIKit then refuses to present.
    func presentPDF(_ doc: SavedPDF) {
        guard !isAlreadyOpen(PDFRemoteViewController.self) else { return }
        guard let url = resolvedPDFFileURL(for: doc) else { return }
        let markLive = !isLiveOutputLocked
        if markLive {
            SlideshowPlaybackController.shared.stop()
            ExternalDisplayManager.shared.presentPDF(url, documentId: doc.id)
            announceAirPlayOverlayIfLinked()
        }
        let remote = PDFRemoteViewController(document: doc, fileURL: url)
        let nav = UINavigationController(rootViewController: remote)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true)
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    func presentMedia(_ item: LibraryItemDTO) {
        if isLiveOutputLocked {
            presentLocalPreview(for: item, in: openShowItems.isEmpty ? displayItems : openShowItems)
            return
        }
        if item.isAvailable == false {
            presentOptions(forItemId: item.id)
            return
        }

        // Captures never go to Apple TV — AirPlay from the phone, downloading first
        // when this device only has the CloudKit metadata.
        if let capture = CaptureStore.shared.record(id: item.id) {
            presentCapture(capture, libraryItem: item)
            return
        }

        SlideshowPlaybackController.shared.stop()

        if item.isVideo {
            AudioPlayerController.shared.stop()
        }

        let startAt = item.isVideo ? (VideoResumeStore.shared.position(for: item.id) ?? 0) : 0
        if connectionManager.sendPlayRequest(id: item.id, startAt: startAt) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if item.isVideo { VideoResumeStore.shared.clear(for: item.id) }
            store.updateCurrentId(item.id)
            ExternalDisplayManager.shared.present(
                .forLibraryItem(
                    item,
                    thumbnail: store.thumbnail(for: item.id),
                    startAt: startAt
                )
            )
        } else {
            presentOfflineLive(for: item)
        }
        reloadLibraryGrid()
    }

    /// Downloads (if needed) then presents a capture via phone AirPlay.
    private func presentCapture(_ capture: CaptureRecord, libraryItem: LibraryItemDTO) {
        SlideshowPlaybackController.shared.stop()
        if capture.isVideo {
            AudioPlayerController.shared.stop()
        }

        let finish: (LibraryItemDTO) -> Void = { [weak self] item in
            guard let self else { return }
            self.presentOfflineLive(for: item)
            self.reloadLibraryGrid()
        }

        let mode = capture.orientation.libraryMode
        if LocalMediaStore.shared.hasMedia(forId: capture.libraryFileName, mode: mode) {
            finish(libraryItem)
            return
        }

        let hud = UIAlertController(
            title: "Downloading…",
            message: "Getting this item from iCloud.",
            preferredStyle: .alert
        )
        present(hud, animated: true)
        EclipseSyncController.shared.backend.downloadAsset(id: capture.id, progress: nil) {
            [weak self] result in
            hud.dismiss(animated: true) {
                switch result {
                case .success:
                    var available = libraryItem
                    available.isAvailable = true
                    finish(available)
                case .failure(let error):
                    let alert = UIAlertController(
                        title: "Download Failed",
                        message: error.localizedDescription,
                        preferredStyle: .alert
                    )
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    self?.present(alert, animated: true)
                }
            }
        }
    }

    // MARK: - Context Menus

    private func contextMenu(for item: HomeGridItem) -> UIMenu? {
        switch item {
        case .camera, .screensaver, .createShow, .addShowMedia:
            return nil
        case .logo:
            var actions: [UIMenuElement] = [
                UIAction(
                    title: "Replace",
                    image: UIImage(systemName: "photo")
                ) { [weak self] _ in
                    self?.onChooseLogo?()
                }
            ]
            if LogoStore.shared.hasCustomImage {
                actions.append(UIAction(
                    title: "Reset to Default",
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { _ in
                    LogoStore.shared.clear()
                })
            }
            return UIMenu(children: actions)
        case .show(let show):
            let rename = UIAction(
                title: "Rename",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.promptRenameShow(show)
            }
            let share = UIAction(
                title: "Share this show",
                image: UIImage(systemName: "person.crop.circle.badge.plus")
            ) { [weak self] _ in
                guard let self else { return }
                EclipseSyncController.shared.backend.presentShareUI(
                    forShowId: show.id,
                    from: self
                )
            }
            let delete = UIAction(
                title: "Delete Show",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmDeleteShow(show)
            }
            return UIMenu(children: [rename, share, delete])
        }
    }

    private func confirmDeleteShow(_ show: LocalAlbum) {
        let alert = UIAlertController(
            title: "Delete Show?",
            message: "“\(show.name)” is removed from Home. Its images and videos stay on this iPhone and any linked EclipseTV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            LocalAlbumStore.shared.delete(id: show.id)
        })
        present(alert, animated: true)
    }

    private func promptRenameShow(_ show: LocalAlbum) {
        presentShowNamePrompt(
            title: "Rename Show",
            initialName: show.name,
            excludingId: show.id,
            confirmTitle: "Save"
        ) { name in
            do {
                try LocalAlbumStore.shared.rename(id: show.id, to: name)
            } catch {
                let alert = UIAlertController(
                    title: "Couldn't Rename Show",
                    message: error.localizedDescription,
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                self.present(alert, animated: true)
            }
        }
    }

    /// Builds the per-item options menu shown via long-press context menu.
    func optionsMenu(for item: LibraryItemDTO) -> UIMenu {
        let id = item.id

        if item.isAvailable == false {
            let resend = UIAction(
                title: "Re-send from Photos",
                image: UIImage(systemName: "arrow.up.circle")
            ) { [weak self] _ in
                self?.onRequestResend?(id)
            }
            let remove = UIAction(
                title: "Remove from Apple TV",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.runCommand {
                    self?.connectionManager.sendDeleteRequest(id: id) ?? false
                }
            }
            return UIMenu(children: [resend, remove])
        }

        let edit = UIAction(
            title: "Edit",
            image: UIImage(systemName: "crop")
        ) { [weak self] _ in
            self?.onRequestEdit?(id)
        }
        let delete = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDelete(id: id, name: item.name)
        }
        // Tap marks phone-live when offline; Preview stays available from ⋯.
        var children: [UIMenuElement] = [
            UIAction(
                title: "Preview",
                image: UIImage(systemName: "eye")
            ) { [weak self] _ in
                self?.presentLocalPreview(for: item)
            }
        ]
        if item.isVideo {
            children.append(contentsOf: videoOptionActions(for: item))
        }
        children.append(contentsOf: [edit, delete])
        return UIMenu(children: children)
    }
}
