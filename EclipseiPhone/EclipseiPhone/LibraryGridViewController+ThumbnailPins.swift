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
        for path in collectionView.indexPathsForVisibleItems {
            if let id = thumbnailPinId(at: path) {
                ids.insert(id)
            }
        }
        // Hero / LIVE chrome also reads `store.thumbnail(for:)`.
        if let currentId = store.currentId {
            ids.insert(currentId)
        }
        store.setVisibleThumbnailIds(ids)
    }

    /// Library media id whose decoded thumb backs the cell at `path`, if any.
    private func thumbnailPinId(at path: IndexPath) -> String? {
        switch homeSection(at: path.section) {
        case .slideshowRibbon:
            let slideIds = SlideshowPlaybackController.shared.activeSlideIds
            guard slideIds.indices.contains(path.item) else { return nil }
            return slideIds[path.item]
        case .shows where isShowMode:
            guard openShowGridItems.indices.contains(path.item) else { return nil }
            switch openShowGridItems[path.item] {
            case .media(let item):
                return item.id
            case .slideshow(let show):
                return show.resolvedCoverId
            default:
                return nil
            }
        case .shows:
            guard showRibbonItems.indices.contains(path.item),
                  case .show(let show) = showRibbonItems[path.item] else { return nil }
            return show.resolvedCoverId
        case .hero, .tools, .none:
            return nil
        }
    }
}
