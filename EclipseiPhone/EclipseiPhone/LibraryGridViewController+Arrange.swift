//
//  LibraryGridViewController+Arrange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Arrange (Show mode media order)

extension LibraryGridViewController {

    /// Starts drag-to-reorder for the open Show's media grid (slideshows stay pinned).
    func beginArranging() {
        guard isShowMode, openShowItems.count >= 2, !isArranging else { return }
        isArranging = true
        reorderGesture.isEnabled = true
        reloadForArrangeChange()
        onArrangingChanged?(true)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        showPresentationToast("Drag to reorder, then tap Done")
    }

    func cancelArranging() {
        guard isArranging else { return }
        endArrangeMode()
    }

    /// Ends arrange mode (order already persisted on each move).
    @discardableResult
    func commitArranging() -> Bool {
        guard isArranging else { return true }
        endArrangeMode()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        return true
    }

    /// Wiggles the tiles the user can drag and dims the ones pinned in place.
    func applyArrangeAppearance(to cell: LibraryThumbnailCell, at indexPath: IndexPath) {
        guard isArranging else {
            cell.setArranging(false)
            cell.alpha = 1
            return
        }
        let movable = collectionView(collectionView, canMoveItemAt: indexPath)
        cell.setArranging(movable)
        cell.alpha = movable ? 1 : 0.4
    }

    @objc func handleReorderGesture(_ gesture: UILongPressGestureRecognizer) {
        guard isArranging, isShowMode else {
            if gesture.state == .began || gesture.state == .changed {
                collectionView.cancelInteractiveMovement()
            }
            return
        }
        switch gesture.state {
        case .began:
            let location = gesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  homeSection(at: indexPath.section) == .shows,
                  canMoveItemAtShowIndex(indexPath.item) else { return }
            collectionView.beginInteractiveMovementForItem(at: indexPath)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(
                gesture.location(in: collectionView)
            )
        case .ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        canMoveItemAt indexPath: IndexPath) -> Bool {
        isArranging
            && isShowMode
            && !showsShowAddTile
            && homeSection(at: indexPath.section) == .shows
            && canMoveItemAtShowIndex(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView,
                        moveItemAt sourceIndexPath: IndexPath,
                        to destinationIndexPath: IndexPath) {
        guard isShowMode,
              homeSection(at: sourceIndexPath.section) == .shows,
              homeSection(at: destinationIndexPath.section) == .shows,
              sourceIndexPath.item != destinationIndexPath.item,
              let albumId = openShowId,
              let ids = openShow?.itemIds else { return }
        let offset = openShowSlideshows.count
        let sourceMedia = sourceIndexPath.item - offset
        let destMedia = destinationIndexPath.item - offset
        var visibleIds = openShowItems.map(\.id)
        guard visibleIds.indices.contains(sourceMedia),
              destMedia >= 0 else { return }
        let moved = visibleIds.remove(at: sourceMedia)
        let dest = min(destMedia, visibleIds.count)
        visibleIds.insert(moved, at: dest)
        let visibleSet = Set(visibleIds)
        let orphans = ids.filter { !visibleSet.contains($0) }
        LocalAlbumStore.shared.reorder(itemIds: visibleIds + orphans, inAlbumId: albumId)
    }

    func collectionView(
        _ collectionView: UICollectionView,
        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
        toProposedIndexPath proposedIndexPath: IndexPath
    ) -> IndexPath {
        guard isArranging, isShowMode,
              homeSection(at: proposedIndexPath.section) == .shows,
              let showsSection = sectionIndex(for: .shows) else {
            return originalIndexPath
        }
        let offset = openShowSlideshows.count
        let mediaCount = openShowItems.count
        guard mediaCount > 0 else { return originalIndexPath }
        let clamped = min(max(proposedIndexPath.item, offset), offset + mediaCount - 1)
        return IndexPath(item: clamped, section: showsSection)
    }

    // MARK: - Private

    private func endArrangeMode() {
        isArranging = false
        reorderGesture.isEnabled = false
        arrangeItems = nil
        reloadForArrangeChange()
        onArrangingChanged?(false)
    }

    /// Cross-fades the grid so tiles ease into (and out of) the wiggle.
    private func reloadForArrangeChange() {
        UIView.transition(
            with: collectionView,
            duration: 0.2,
            options: .transitionCrossDissolve
        ) {
            self.collectionView.reloadData()
        }
    }

    /// Media rows are movable; slideshow tiles stay pinned at the front.
    private func canMoveItemAtShowIndex(_ item: Int) -> Bool {
        let offset = openShowSlideshows.count
        return item >= offset && item < offset + openShowItems.count
    }
}
