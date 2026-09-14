//
//  LibraryGridViewController+GridHelpers.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Grid Helpers

extension LibraryGridViewController {
    func updateEmptyState() {
        // Show mode owns its empty Add tile; Home shows Recent from both modes.
        refreshMusicSwipeHintVisibility()
        guard !isShowMode else {
            emptyLabel.isHidden = true
            return
        }
        let hasShows = !LocalAlbumStore.shared.albums.isEmpty
        if !hasShows {
            emptyLabel.text = String(localized: "Create a Show to get started.")
            emptyLabel.isHidden = false
            // Sit just below the lone New Show tile rather than over it.
            let tile = Self.homeRecentTileSize(
                containerWidth: collectionView.bounds.width,
                sectionInset: sectionInset,
                spacing: interitemSpacing
            )
            emptyTopConstraint?.constant = collectionView.contentInset.top
                + Self.heroBandHeight(
                    containerWidth: collectionView.bounds.width,
                    containerHeight: collectionView.bounds.height,
                    sectionInset: sectionInset,
                    horizontalSizeClass: traitCollection.horizontalSizeClass
                )
                + Self.showsGridTopInset
                + Self.sectionHeaderEstimatedHeight
                + tile.height
                + sectionInset * 2
        } else {
            emptyLabel.isHidden = true
        }
    }

    /// Compact paging can swipe to Music; side-by-side layout cannot.
    func setMusicPagingAvailable(_ available: Bool) {
        musicSwipeHint.setMusicPagingAvailable(available)
        refreshMusicSwipeHintVisibility()
    }

    /// Music swipe tip is Home-only — never Show mode or any other surface.
    func refreshMusicSwipeHintVisibility() {
        guard !isShowMode else {
            musicSwipeHint.isHidden = true
            return
        }
        musicSwipeHint.reload()
    }

    /// Permanently hides the Home Music swipe hint after dismiss or first visit.
    func dismissMusicSwipeHint() {
        musicSwipeHint.dismissPermanently()
        refreshMusicSwipeHintVisibility()
    }

    /// Rebuilds the Show page layout. Home keeps its own layout.
    func applyCollectionLayout() {
        applyShowPageLayout()
    }

    /// Keeps Home and Show pages rubber-bandable even when the grid fits on screen.
    func updateHomeVerticalScrollPolicy() {
        collectionView.alwaysBounceVertical = true
        collectionView.bounces = true
        collectionView.isScrollEnabled = true
        // Don't yank the offset while the user is mid-bounce.
        guard !collectionView.isDragging, !collectionView.isDecelerating else { return }
        if maxVerticalScroll() <= Self.negligibleVerticalScroll {
            pinCollectionViewToTop()
        }
    }

    /// Pins the grid to its top inset (no residual overscroll under the header).
    func pinCollectionViewToTop() {
        let top = -collectionView.adjustedContentInset.top
        if abs(collectionView.contentOffset.y - top) > 0.5 {
            collectionView.setContentOffset(CGPoint(x: 0, y: top), animated: false)
        }
    }

    /// Repaints only the Camera tile (live preview / last-frame updates).
    ///
    /// In place and unanimated, like every other partial update on this grid. The
    /// last frame is captured on the same taps that change what is live, so an
    /// animated `reloadItems` here was crossfading a replacement cell in exactly
    /// when the go-live `reloadData()` landed — and the losing cell kept its stroke.
    func reloadCameraTile() {
        guard let showsSection = sectionIndex(for: .shows),
              let item = cameraShowItemIndex else { return }
        let indexPath = IndexPath(item: item, section: showsSection)
        guard collectionView.indexPathsForVisibleItems.contains(indexPath) else {
            return
        }
        UIView.performWithoutAnimation {
            collectionView.reconfigureItems(at: [indexPath])
        }
    }
}
