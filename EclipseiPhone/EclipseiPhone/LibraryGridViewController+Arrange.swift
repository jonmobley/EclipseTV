//
//  LibraryGridViewController+Arrange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Arrange (Show mode surface order)

extension LibraryGridViewController {

    /// Starts drag-to-reorder for the open Show's grid (slideshows stay pinned last).
    func beginArranging() {
        beginArranging(preservingGesture: false)
    }

    /// - Parameter preservingGesture: When true (long-press enter), skip reload so the
    ///   same touch can begin an interactive move.
    private func beginArranging(preservingGesture: Bool) {
        guard isShowMode, openShowMovableCount >= 2, !isArranging else { return }
        if isSelecting {
            cancelSelecting()
        }
        // Add tile drops out of the data source when arranging; must reload or
        // the collection view count disagrees with `openShowGridItems`.
        let mustReload = showsShowAddTile || !preservingGesture
        isArranging = true
        reorderGesture.minimumPressDuration = 0.15
        if mustReload {
            reloadForArrangeChange()
        } else {
            for case let cell as LibraryThumbnailCell in collectionView.visibleCells {
                guard let indexPath = collectionView.indexPath(for: cell) else { continue }
                applyArrangeAppearance(to: cell, at: indexPath)
                cell.clearMoreMenu()
            }
        }
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
        let location = gesture.location(in: collectionView)

        switch gesture.state {
        case .began:
            guard isShowMode, !isSelecting else { return }
            guard let startPath = collectionView.indexPathForItem(at: location),
                  homeSection(at: startPath.section) == .shows else { return }

            if !isArranging {
                guard openShowMovableCount >= 2 else { return }
                beginArranging(preservingGesture: true)
            }

            // Hit-test again — entering arrange may reload (Add tile drops out).
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  homeSection(at: indexPath.section) == .shows,
                  canMoveItemAtShowIndex(indexPath.item) else { return }
            collectionView.beginInteractiveMovementForItem(at: indexPath)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        case .changed:
            guard isArranging else { return }
            collectionView.updateInteractiveMovementTargetPosition(location)

        case .ended:
            guard isArranging else { return }
            collectionView.endInteractiveMovement()

        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    func collectionView(_ collectionView: UICollectionView,
                        canMoveItemAt indexPath: IndexPath) -> Bool {
        isArranging
            && isShowMode
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
              let album = openShow else { return }
        // Surface leads the grid; slideshows are pinned after it.
        let sourceSurface = sourceIndexPath.item
        let destSurface = destinationIndexPath.item
        var surface = album.resolvedSurfaceIds
        guard surface.indices.contains(sourceSurface),
              destSurface >= 0 else { return }
        let moved = surface.remove(at: sourceSurface)
        let dest = min(destSurface, surface.count)
        surface.insert(moved, at: dest)
        LocalAlbumStore.shared.reorderSurface(surface, albumId: albumId)
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
        let surfaceCount = openShow?.resolvedSurfaceIds.count ?? 0
        guard surfaceCount > 0 else { return originalIndexPath }
        let clamped = min(max(proposedIndexPath.item, 0), surfaceCount - 1)
        return IndexPath(item: clamped, section: showsSection)
    }

    // MARK: - Private

    private func endArrangeMode() {
        isArranging = false
        arrangeItems = nil
        reorderGesture.minimumPressDuration = 0.45
        reloadForArrangeChange()
        onArrangingChanged?(false)
    }

    /// Cross-fades the grid so tiles ease into (and out of) the wiggle.
    ///
    /// Uses `reloadLibraryGrid` so visible thumbs stay pinned — a bare
    /// `reloadData()` after an `NSCache` purge blanked every media tile, and
    /// `didUpdateThumbnailFor` used to no-op while arranging so they never
    /// came back until Done.
    private func reloadForArrangeChange() {
        UIView.transition(
            with: collectionView,
            duration: 0.2,
            options: .transitionCrossDissolve
        ) {
            self.reloadLibraryGrid()
        }
    }

    /// Surface rows (tools + members) are movable; trailing slideshow tiles stay pinned.
    private func canMoveItemAtShowIndex(_ item: Int) -> Bool {
        let surfaceCount = openShow?.resolvedSurfaceIds.count ?? 0
        return item >= 0 && item < surfaceCount
    }
}
