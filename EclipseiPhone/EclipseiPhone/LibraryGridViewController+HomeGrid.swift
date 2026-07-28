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
        visibleHomeSections.count
    }

    func collectionView(_ collectionView: UICollectionView,
                        numberOfItemsInSection section: Int) -> Int {
        guard let homeSection = homeSection(at: section) else { return 0 }
        switch homeSection {
        case .tools: return toolItems.count
        case .slideshowRibbon: return liveSlideshowRibbonItemCount()
        case .shows:
            return isShowMode ? numberOfShowModeItems() : showRibbonItems.count
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LibraryThumbnailCell.reuseIdentifier,
            for: indexPath
        ) as! LibraryThumbnailCell

        guard let section = homeSection(at: indexPath.section) else { return cell }
        switch section {
        case .slideshowRibbon:
            configureLiveSlideshowRibbonCell(cell, at: indexPath)
        case .shows where isShowMode:
            configureShowModeCell(cell, at: indexPath)
        case .tools, .shows:
            guard let item = homeItem(at: indexPath) else { return cell }
            configure(cell, with: item)
        }
        return cell
    }

    func collectionView(
        _ collectionView: UICollectionView,
        viewForSupplementaryElementOfKind kind: String,
        at indexPath: IndexPath
    ) -> UICollectionReusableView {
        let header = collectionView.dequeueReusableSupplementaryView(
            ofKind: kind,
            withReuseIdentifier: HomeSectionHeaderView.reuseIdentifier,
            for: indexPath
        ) as! HomeSectionHeaderView
        switch homeSection(at: indexPath.section) {
        case .slideshowRibbon:
            let name = activeLiveSlideshow()?.name ?? "Slideshow"
            header.configure(title: name)
        default:
            header.configure(title: "Recent")
        }
        return header
    }

    func collectionView(_ collectionView: UICollectionView,
                        didSelectItemAt indexPath: IndexPath) {
        guard !isArranging else { return }
        switch homeSection(at: indexPath.section) {
        case .slideshowRibbon:
            handleLiveSlideshowRibbonTap(at: indexPath)
        case .shows where isShowMode:
            handleShowModeTap(at: indexPath)
        default:
            guard let item = homeItem(at: indexPath) else { return }
            handleTap(item)
        }
    }

    func collectionView(
        _ collectionView: UICollectionView,
        contextMenuConfigurationForItemAt indexPath: IndexPath,
        point: CGPoint
    ) -> UIContextMenuConfiguration? {
        guard !isArranging else { return nil }
        switch homeSection(at: indexPath.section) {
        case .slideshowRibbon:
            return nil
        case .shows where isShowMode:
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self] _ in
                self?.showModeContextMenu(at: indexPath)
            }
        default:
            guard let item = homeItem(at: indexPath) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) {
                [weak self] _ in
                self?.contextMenu(for: item)
            }
        }
    }

    // MARK: - Cell Config

    private func configure(_ cell: LibraryThumbnailCell, with item: HomeGridItem) {
        switch item {
        case .logo:
            cell.configureSpecial(
                title: "Logo",
                systemImage: "seal.fill",
                thumbnail: LogoStore.shared.image,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: isLogoSelected && !ExternalDisplayManager.shared.isOverlayLive,
                thumbnailContentMode: .scaleAspectFill
            )
        case .camera:
            cell.configureCamera(
                isLive: ExternalDisplayManager.shared.isCameraLive,
                lastFrame: CameraManager.shared.lastFrame
            )
        case .website:
            let mgr = ExternalDisplayManager.shared
            let isLive = mgr.isWebLive && mgr.liveWebPageId == WebPage.freeBrowseId
            cell.configureSpecial(
                title: "Website",
                systemImage: "safari",
                thumbnail: WebThumbnailStore.shared.image(for: WebPage.freeBrowseId),
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: isLive
            )
        case .createShow:
            cell.configureActionTile(title: "New Show", systemImage: "plus")
        case .show(let show):
            let coverId = show.resolvedCoverId
            let thumb = coverId.flatMap { store.thumbnail(for: $0) }
            let isLiveShow = show.itemIds.contains(where: { $0 == store.currentId })
                && !isBlackSelected
                && !isLogoSelected
                && !ExternalDisplayManager.shared.isOverlayLive
            cell.configureSpecial(
                title: show.name,
                systemImage: "rectangle.stack.fill",
                thumbnail: thumb,
                fillColor: UIColor(white: 0.16, alpha: 1),
                isLive: isLiveShow
            )
        }
    }

    // MARK: - Taps

    private func handleTap(_ item: HomeGridItem) {
        switch item {
        case .logo:
            isBlackSelected = false
            presentLogoLive()
        case .camera:
            isBlackSelected = false
            isLogoSelected = false
            onPresentCamera?()
        case .website:
            isBlackSelected = false
            isLogoSelected = false
            presentFreeBrowseWebsite()
        case .createShow:
            onCreateShow?()
        case .show(let show):
            isBlackSelected = false
            isLogoSelected = false
            openLocalAlbum(id: show.id)
        }
    }

    /// Presents a solid black frame on AirPlay (header Black control).
    func presentBlackLive() {
        SlideshowPlaybackController.shared.stop()
        isBlackSelected = true
        isLogoSelected = false
        ExternalDisplayManager.shared.presentBlack()
        warnIfNoExternalDisplay()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        collectionView.reloadData()
        refreshLiveHeader()
    }

    /// Marks Logo live and presents it on AirPlay when a file is available.
    func presentLogoLive() {
        guard let url = LogoStore.shared.fileURL else {
            onChooseLogo?()
            return
        }
        SlideshowPlaybackController.shared.stop()
        isBlackSelected = false
        isLogoSelected = true
        ExternalDisplayManager.shared.present(.image(url))
        warnIfNoExternalDisplay()
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        collectionView.reloadData()
        refreshLiveHeader()
    }

    /// Opens the home Website tile: a free browser for any HTTPS address.
    func presentFreeBrowseWebsite() {
        let mgr = ExternalDisplayManager.shared
        var page = WebPage.freeBrowse
        if mgr.liveWebPageId == WebPage.freeBrowseId,
           case .web(let url) = mgr.overlaySource,
           url.absoluteString != "about:blank" {
            page = WebPage(id: WebPage.freeBrowseId, title: "Website", url: url)
        }
        presentWebPage(page)
    }

    /// Presents a website (saved bookmark or home free-browse session).
    func presentWebPage(_ page: WebPage) {
        SlideshowPlaybackController.shared.stop()
        ExternalDisplayManager.shared.presentWeb(page.url, pageId: page.id)
        let remote = WebRemoteViewController(page: page)
        let nav = UINavigationController(rootViewController: remote)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true) {
            remote.warnIfNoExternalDisplay()
        }
        collectionView.reloadData()
        refreshLiveHeader()
    }

    /// Presents a saved PDF (from + → PDF).
    func presentPDF(_ doc: SavedPDF) {
        SlideshowPlaybackController.shared.stop()
        guard let url = PDFStore.shared.fileURL(for: doc.id) else {
            let alert = UIAlertController(
                title: "PDF Missing",
                message: "That file is no longer on this iPhone.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        ExternalDisplayManager.shared.presentPDF(url, documentId: doc.id)
        let remote = PDFRemoteViewController(document: doc, fileURL: url)
        let nav = UINavigationController(rootViewController: remote)
        nav.modalPresentationStyle = .fullScreen
        present(nav, animated: true) {
            remote.warnIfNoExternalDisplay()
        }
        collectionView.reloadData()
        refreshLiveHeader()
    }

    func presentMedia(_ item: LibraryItemDTO) {
        if item.isAvailable == false {
            presentOptions(forItemId: item.id)
            return
        }

        SlideshowPlaybackController.shared.stop()

        if item.isVideo {
            AudioPlayerController.shared.stop()
        }

        if connectionManager.sendPlayRequest(id: item.id) {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            store.updateCurrentId(item.id)
            ExternalDisplayManager.shared.present(
                .forLibraryItem(item, thumbnail: store.thumbnail(for: item.id))
            )
        } else {
            presentOfflineLive(for: item)
        }
        collectionView.reloadData()
    }

    // MARK: - Context Menus

    private func contextMenu(for item: HomeGridItem) -> UIMenu? {
        switch item {
        case .camera, .website, .createShow:
            return nil
        case .logo:
            let choose = UIAction(
                title: LogoStore.shared.hasCustomImage ? "Change Image" : "Choose Image",
                image: UIImage(systemName: "photo")
            ) { [weak self] _ in
                self?.onChooseLogo?()
            }
            var actions: [UIMenuElement] = [choose]
            if LogoStore.shared.hasCustomImage {
                let remove = UIAction(
                    title: "Reset to App Icon",
                    image: UIImage(systemName: "arrow.counterclockwise"),
                    attributes: .destructive
                ) { [weak self] _ in
                    LogoStore.shared.clear()
                    if self?.isLogoSelected == true {
                        self?.presentLogoLive()
                    } else {
                        self?.collectionView.reloadData()
                        self?.refreshLiveHeader()
                    }
                }
                actions.append(remove)
            }
            return UIMenu(children: actions)
        case .show(let show):
            let rename = UIAction(
                title: "Rename",
                image: UIImage(systemName: "pencil")
            ) { [weak self] _ in
                self?.promptRenameShow(show)
            }
            let delete = UIAction(
                title: "Delete Show",
                image: UIImage(systemName: "trash"),
                attributes: .destructive
            ) { [weak self] _ in
                self?.confirmDeleteShow(show)
            }
            return UIMenu(children: [rename, delete])
        }
    }

    private func confirmDeleteShow(_ show: LocalAlbum) {
        let alert = UIAlertController(
            title: "Delete Show?",
            message: "“\(show.name)” is removed from Home. Its photos and videos stay on this iPhone and any linked EclipseTV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            SlideshowStore.shared.deleteAll(forShowId: show.id)
            LocalAlbumStore.shared.delete(id: show.id)
        })
        present(alert, animated: true)
    }

    private func promptRenameShow(_ show: LocalAlbum) {
        let alert = UIAlertController(
            title: "Rename Show", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = show.name
            field.autocapitalizationType = .words
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in
            let name = alert.textFields?.first?.text ?? ""
            try? LocalAlbumStore.shared.rename(id: show.id, to: name)
        })
        present(alert, animated: true)
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

        let preview = UIAction(
            title: "Preview",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.presentLocalPreview(for: item)
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
        return UIMenu(children: [preview, edit, delete])
    }
}
