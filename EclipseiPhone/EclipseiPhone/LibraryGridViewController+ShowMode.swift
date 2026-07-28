//
//  LibraryGridViewController+ShowMode.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Mode (in-place home shell)

extension LibraryGridViewController {

    /// Opens a Show from the Eclipse menu or a home-grid tile.
    func openLocalAlbum(id: UUID) {
        guard let album = LocalAlbumStore.shared.album(id: id) else { return }
        enterShowMode(album)
    }

    /// Leaves Show mode and restores the Recent Shows ribbon.
    func closeOpenShow() {
        guard openShowId != nil else { return }
        if isArranging {
            cancelArranging()
        }
        openShowId = nil
        applyCollectionLayout()
        collectionView.reloadData()
        updateEmptyState()
        onOpenShowChanged?(nil)
    }

    /// Closes Show mode when the open Show is missing or in another Display Mode.
    func validateOpenShow() {
        guard let id = openShowId else { return }
        guard let album = LocalAlbumStore.shared.album(id: id),
              album.orientation == ExternalOutputSettings.orientation else {
            closeOpenShow()
            return
        }
        onOpenShowChanged?(album)
    }

    /// Prompts to rename the open Show.
    func promptRenameOpenShow() {
        guard let show = openShow else { return }
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

    /// Confirms and deletes the open Show, then returns Home.
    func confirmDeleteOpenShow() {
        guard let show = openShow else { return }
        let alert = UIAlertController(
            title: "Delete Show?",
            message: "“\(show.name)” is removed from Home. Its photos and videos stay on this iPhone and any linked EclipseTV.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            SlideshowStore.shared.deleteAll(forShowId: show.id)
            LocalAlbumStore.shared.delete(id: show.id)
            self?.closeOpenShow()
        })
        present(alert, animated: true)
    }

    // MARK: - Enter

    private func enterShowMode(_ album: LocalAlbum) {
        if isArranging {
            cancelArranging()
        }
        LocalAlbumStore.shared.touchRecentlyOpened(id: album.id)
        if ExternalOutputSettings.orientation != album.orientation {
            ExternalOutputSettings.orientation = album.orientation
        }
        let wasShowMode = isShowMode
        openShowId = album.id
        if !wasShowMode {
            applyCollectionLayout()
        }
        collectionView.reloadData()
        updateEmptyState()
        onOpenShowChanged?(album)
    }

    // MARK: - Show Grid Cells / Actions

    func numberOfShowModeItems() -> Int {
        openShowGridItems.count
    }

    func configureShowModeCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return }
        switch items[indexPath.item] {
        case .add:
            cell.configureActionTile(title: "Add", systemImage: "plus")
        case .slideshow(let show):
            let cover = show.resolvedCoverId.flatMap { store.thumbnail(for: $0) }
            cell.configureSpecial(
                title: show.name,
                systemImage: "rectangle.stack.fill",
                thumbnail: cover,
                fillColor: .darkGray,
                isLive: SlideshowPlaybackController.shared.isLive(slideshowId: show.id)
                    && !isBlackSelected
                    && !isLogoSelected
            )
        case .media(let item):
            cell.configure(
                with: item,
                thumbnail: store.thumbnail(for: item.id),
                isLive: item.id == store.currentId
                    && SlideshowPlaybackController.shared.activeSlideshowId == nil
                    && !isBlackSelected
                    && !isLogoSelected
                    && !ExternalDisplayManager.shared.isOverlayLive
            )
        }
    }

    func handleShowModeTap(at indexPath: IndexPath) {
        guard !isArranging else { return }
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return }
        switch items[indexPath.item] {
        case .add:
            presentShowAddSheet()
        case .slideshow(let show):
            isBlackSelected = false
            isLogoSelected = false
            presentSlideshow(show)
        case .media(let item):
            isBlackSelected = false
            isLogoSelected = false
            SlideshowPlaybackController.shared.stop()
            presentMedia(item)
        }
    }

    func showModeContextMenu(at indexPath: IndexPath) -> UIMenu? {
        guard !isArranging, let album = openShow else { return nil }
        let items = openShowGridItems
        guard items.indices.contains(indexPath.item) else { return nil }
        switch items[indexPath.item] {
        case .add:
            return nil
        case .slideshow(let show):
            return slideshowContextMenu(show)
        case .media(let item):
            return mediaContextMenu(item, in: album)
        }
    }

    /// Presents the slideshow on AirPlay / Multipeer.
    func presentSlideshow(_ slideshow: Slideshow) {
        guard !slideshow.itemIds.isEmpty else {
            presentSlideshowEditor(slideshow.id)
            return
        }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        SlideshowPlaybackController.shared.play(
            slideshow,
            connectionManager: connectionManager
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

    private func presentShowAddSheet() {
        guard let id = openShowId else { return }
        let sheet = UIAlertController(title: nil, message: nil, preferredStyle: .actionSheet)
        sheet.addAction(UIAlertAction(title: "Import…", style: .default) { [weak self] _ in
            self?.onAddMediaToAlbum?(id)
        })
        sheet.addAction(UIAlertAction(title: "New Slideshow…", style: .default) { [weak self] _ in
            self?.onCreateSlideshow?(id)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = collectionView
            popover.sourceRect = collectionView.bounds
        }
        present(sheet, animated: true)
    }

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
        return UIMenu(children: [edit, rename, delete])
    }

    private func mediaContextMenu(_ item: LibraryItemDTO, in album: LocalAlbum) -> UIMenu {
        let items = openShowItems
        let isCover = album.resolvedCoverId == item.id
        let preview = UIAction(
            title: "Preview",
            image: UIImage(systemName: "eye")
        ) { [weak self] _ in
            self?.presentLocalPreview(for: item, in: items)
        }
        let cover = UIAction(
            title: isCover ? "Cover Photo" : "Set as Cover",
            image: UIImage(systemName: isCover ? "star.fill" : "star"),
            attributes: isCover ? [.disabled] : []
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.setCover(itemId: item.id, albumId: id)
        }
        let remove = UIAction(
            title: "Remove from Show",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.remove(itemId: item.id, fromAlbumId: id)
        }
        return UIMenu(children: [preview, cover, remove])
    }

    private func promptRenameSlideshow(_ show: Slideshow) {
        let alert = UIAlertController(
            title: "Rename Slideshow", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.text = show.name
            field.autocapitalizationType = .words
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
            message: "“\(show.name)” is removed. Its photos stay in your library.",
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
}
