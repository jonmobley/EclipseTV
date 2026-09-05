//
//  LibraryGridViewController+ThumbnailPins.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Visible Thumbnail Pins

extension LibraryGridViewController {

    /// Pins on-screen media thumbs so an `NSCache` purge can’t blank the grid.
    func refreshVisibleThumbnailPins() {
        var ids = Set<String>()
        let visible = collectionView.indexPathsForVisibleItems
        if visible.isEmpty {
            ids.formUnion(fallbackOnScreenThumbnailIds())
        } else {
            for path in visible {
                if let id = thumbnailPinId(at: path, in: collectionView) {
                    ids.insert(id)
                }
            }
        }
        if docksLiveSlideshowRibbon {
            let slideIds = SlideshowPlaybackController.shared.activeSlideIds
            for path in slideshowRibbonView.indexPathsForVisibleItems {
                guard slideIds.indices.contains(path.item) else { continue }
                ids.insert(slideIds[path.item])
            }
        }
        // Hero / LIVE chrome also reads `store.thumbnail(for:)`.
        if let currentId = store.currentId {
            ids.insert(currentId)
        }
        store.setVisibleThumbnailIds(ids)
    }

    /// Pins the thumb for a cell that just appeared, without walking the grid.
    func pinArrivingThumbnail(
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) {
        guard let id = thumbnailPinId(at: indexPath, in: collectionView) else { return }
        store.pinVisibleThumbnailId(id)
    }

    /// Paints a thumb that just landed onto visible placeholders.
    ///
    /// Does not `reloadItems` — that hitches a fling and rebuilds ⋯ menus. Tiles
    /// that have not appeared yet pick the image up in `cellForItemAt`.
    func paintArrivedThumbnail(_ id: String) {
        store.pinVisibleThumbnailId(id)
        paintVisibleCells(showing: id, in: collectionView)
        if docksLiveSlideshowRibbon {
            paintVisibleCells(showing: id, in: slideshowRibbonView)
        }
    }

    /// Fills a placeholder cell when it appears if the store has the preview now.
    func fillPlaceholderThumbnailIfReady(
        _ cell: UICollectionViewCell,
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) {
        applyLoadedThumbnailIfNeeded(to: cell, at: indexPath, in: collectionView)
    }

    /// Library media id whose decoded thumb backs the cell at `path`, if any.
    func thumbnailPinId(at path: IndexPath) -> String? {
        thumbnailPinId(at: path, in: collectionView)
    }

    /// Kicks off a disk decode for tiles about to appear.
    func prefetchThumbnails(
        at indexPaths: [IndexPath],
        in collectionView: UICollectionView
    ) {
        for path in indexPaths {
            guard let id = thumbnailPinId(at: path, in: collectionView) else {
                continue
            }
            _ = store.thumbnail(for: id)
        }
    }

    /// Home, Show, or the docked live-slideshow strip.
    func isLibraryThumbnailScrollView(_ scrollView: UIScrollView) -> Bool {
        scrollView === collectionView || scrollView === slideshowRibbonView
    }

    // MARK: - Private

    private func fallbackOnScreenThumbnailIds() -> Set<String> {
        var ids = Set<String>()
        if isShowMode {
            for item in openShowGridItems.prefix(16) {
                if let id = item.libraryThumbnailId { ids.insert(id) }
            }
        } else {
            for item in showRibbonItems.prefix(8) {
                if case .show(let show) = item, let cover = show.resolvedCoverId {
                    ids.insert(cover)
                }
            }
        }
        return ids
    }

    private func paintVisibleCells(showing id: String, in view: UICollectionView) {
        for path in view.indexPathsForVisibleItems {
            guard thumbnailPinId(at: path, in: view) == id,
                  let cell = view.cellForItem(at: path) else { continue }
            applyLoadedThumbnailIfNeeded(to: cell, at: path, in: view)
        }
    }

    private func applyLoadedThumbnailIfNeeded(
        to cell: UICollectionViewCell,
        at indexPath: IndexPath,
        in collectionView: UICollectionView
    ) {
        guard let id = thumbnailPinId(at: indexPath, in: collectionView) else { return }
        guard let image = store.thumbnail(for: id) else { return }
        if let thumbCell = cell as? LibraryThumbnailCell, thumbCell.isShowingPlaceholder {
            thumbCell.applyLoadedThumbnail(image)
        } else if let showCell = cell as? HomeShowTileCell, showCell.isShowingPlaceholder {
            showCell.applyLoadedCover(image)
        }
    }

    private func thumbnailPinId(
        at path: IndexPath,
        in collectionView: UICollectionView
    ) -> String? {
        if isDockedSlideshowRibbon(collectionView) {
            let slideIds = SlideshowPlaybackController.shared.activeSlideIds
            guard slideIds.indices.contains(path.item) else { return nil }
            return slideIds[path.item]
        }
        switch homeSection(at: path.section, in: collectionView) {
        case .slideshowRibbon:
            let slideIds = SlideshowPlaybackController.shared.activeSlideIds
            guard slideIds.indices.contains(path.item) else { return nil }
            return slideIds[path.item]
        case .shows where isShowMode:
            guard openShowGridItems.indices.contains(path.item) else { return nil }
            return openShowGridItems[path.item].libraryThumbnailId
        case .shows:
            guard showRibbonItems.indices.contains(path.item),
                  case .show(let show) = showRibbonItems[path.item] else { return nil }
            return show.resolvedCoverId
        case .hero, .tools, .none:
            return nil
        }
    }
}

// MARK: - Prefetch

extension LibraryGridViewController: UICollectionViewDataSourcePrefetching {

    func collectionView(
        _ collectionView: UICollectionView,
        prefetchItemsAt indexPaths: [IndexPath]
    ) {
        prefetchThumbnails(at: indexPaths, in: collectionView)
    }
}
