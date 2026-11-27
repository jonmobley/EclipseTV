//
//  LibraryGridViewController+Arrange.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Arrange (Show mode surface order)

extension LibraryGridViewController {

    /// Starts drag-to-reorder for the open Show's grid (including slideshows).
    func beginArranging() {
        beginArranging(preservingGesture: false)
    }

    /// - Parameter preservingGesture: When true (long-press enter), skip reload so the
    ///   same touch can begin an interactive move.
    private func beginArranging(preservingGesture: Bool) {
        guard isShowMode, openShowMovableCount >= 2, !isArranging else { return }
        // Positions while arranging are positions in the whole Show, so a filtered
        // grid would save the wrong order.
        guard !(preservingGesture && isSearchingShow) else { return }
        if isSearchingShow {
            setShowSearchQuery("")
            onShowSearchEnded?()
        }
        if isSelecting {
            cancelSelecting()
        }
        // Add tile drops out of the data source when arranging; must reload or
        // the collection view count disagrees with `openShowGridItems`.
        let mustReload = showsShowAddTile || !preservingGesture
        isArranging = true
        arrangeStartSurface = openShowSurfaceIds
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
        Haptics.impactRigid()
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
        let start = arrangeStartSurface
        let showId = openShowId
        let changed = start != nil && start != openShowSurfaceIds
        endArrangeMode()
        Haptics.success()
        if changed, let start, let showId {
            offerArrangeUndo(restoring: start, showId: showId)
        }
        return true
    }

    /// Undo toast after Done: puts the grid back in the order Arrange started from.
    /// Cards added or removed since (another device, say) are respected.
    private func offerArrangeUndo(restoring start: [String], showId: UUID) {
        showUndoToast("Order changed") {
            guard let album = LocalAlbumStore.shared.album(id: showId) else { return }
            let current = album.surfaceIds ?? album.resolvedSurfaceIds
            LocalAlbumStore.shared.reorderSurface(
                ArrangeUndo.restoredOrder(original: start, current: current),
                albumId: showId
            )
        }
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
            Haptics.impactMedium()

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
        collectionView === showCollectionView
            && isArranging
            && isShowMode
            && homeSection(at: indexPath.section, in: collectionView) == .shows
            && canMoveItemAtShowIndex(indexPath.item)
    }

    func collectionView(_ collectionView: UICollectionView,
                        moveItemAt sourceIndexPath: IndexPath,
                        to destinationIndexPath: IndexPath) {
        guard collectionView === showCollectionView,
              isShowMode,
              homeSection(at: sourceIndexPath.section, in: collectionView) == .shows,
              homeSection(at: destinationIndexPath.section, in: collectionView) == .shows,
              sourceIndexPath.item != destinationIndexPath.item,
              let albumId = openShowId else { return }
        // Surface leads the grid; Add (if any) stays after it.
        let sourceSurface = sourceIndexPath.item
        let destSurface = destinationIndexPath.item
        var surface = openShowSurfaceIds
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
        guard collectionView === showCollectionView,
              isArranging, isShowMode,
              homeSection(at: proposedIndexPath.section, in: collectionView) == .shows,
              let showsSection = sectionIndex(for: .shows) else {
            return originalIndexPath
        }
        let surfaceCount = openShowSurfaceIds.count
        guard surfaceCount > 0 else { return originalIndexPath }
        let clamped = min(max(proposedIndexPath.item, 0), surfaceCount - 1)
        return IndexPath(item: clamped, section: showsSection)
    }

    // MARK: - Private

    private func endArrangeMode() {
        isArranging = false
        arrangeStartSurface = nil
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

    /// Surface rows (tools, members, slideshows) are movable; Add stays pinned.
    private func canMoveItemAtShowIndex(_ item: Int) -> Bool {
        let surfaceCount = openShowSurfaceIds.count
        return item >= 0 && item < surfaceCount
    }
}

// MARK: - Undo order

/// Pure rule for undoing an Arrange.
enum ArrangeUndo {

    /// `original` order for the cards still in `current`, then any card that
    /// arrived since in its current place at the end. Removed cards stay removed.
    /// - Parameters:
    ///   - original: Grid order when Arrange began.
    ///   - current: Grid order now.
    /// - Returns: The order to save.
    static func restoredOrder(original: [String], current: [String]) -> [String] {
        let currentSet = Set(current)
        let kept = original.filter { currentSet.contains($0) }
        let keptSet = Set(kept)
        return kept + current.filter { !keptSet.contains($0) }
    }
}
