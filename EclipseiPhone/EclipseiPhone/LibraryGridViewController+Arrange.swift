// LibraryGridViewController+Arrange.swift
import UIKit

// MARK: - Drag-and-Drop Arranging

/// Adds an "Arrange" mode to the library grid. While arranging, the user reorders
/// available items by dragging; saving sends the full new order to the Apple TV as a
/// single `reorder_items` command. Unavailable (purged) items stay pinned at the end
/// and can't be dragged.
extension LibraryGridViewController {

    /// Number of leading items that are available (and therefore reorderable). The
    /// Apple TV manifest always lists available items first, then purged ones.
    var availableCount: Int {
        displayItems.filter { $0.isAvailable != false }.count
    }

    // MARK: - Mode Transitions

    /// Enters arrange mode, snapshotting the current order as the working copy.
    func beginArranging() {
        guard !isArranging, !store.items.isEmpty else { return }
        isArranging = true
        arrangeItems = store.items
        reorderGesture.isEnabled = true
        collectionView.reloadData()
    }

    /// Discards the in-progress arrangement and returns to the mirrored order.
    func cancelArranging() {
        guard isArranging else { return }
        isArranging = false
        reorderGesture.isEnabled = false
        arrangeItems = nil
        collectionView.reloadData()
    }

    /// Saves the arrangement by sending the new order to the Apple TV. Returns false
    /// (and stays in arrange mode) if there's no connection to receive it. The working
    /// order is kept on screen until the TV confirms with a fresh manifest, avoiding a
    /// flash back to the previous order.
    @discardableResult
    func commitArranging() -> Bool {
        guard isArranging else { return true }

        let orderedIds = displayItems
            .filter { $0.isAvailable != false }
            .map { $0.id }

        guard connectionManager.sendReorderRequest(orderedIds: orderedIds) else {
            let alert = UIAlertController(title: "Not Connected",
                                          message: "Reconnect to your Apple TV and try again.",
                                          preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return false
        }

        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        isArranging = false
        reorderGesture.isEnabled = false
        collectionView.reloadData()
        return true
    }

    // MARK: - Interactive Movement

    @objc func handleReorderGesture(_ gesture: UILongPressGestureRecognizer) {
        switch gesture.state {
        case .began:
            let location = gesture.location(in: collectionView)
            guard let indexPath = collectionView.indexPathForItem(at: location),
                  let item = displayItem(at: indexPath.item), item.isAvailable != false else {
                return
            }
            collectionView.beginInteractiveMovementForItem(at: indexPath)
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .changed:
            collectionView.updateInteractiveMovementTargetPosition(gesture.location(in: collectionView))
        case .ended:
            collectionView.endInteractiveMovement()
        default:
            collectionView.cancelInteractiveMovement()
        }
    }

    // MARK: - Reorder Data Source / Delegate

    func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
        guard isArranging, let item = displayItem(at: indexPath.item) else { return false }
        return item.isAvailable != false
    }

    func collectionView(_ collectionView: UICollectionView,
                        moveItemAt sourceIndexPath: IndexPath,
                        to destinationIndexPath: IndexPath) {
        var items = displayItems
        guard sourceIndexPath.item < items.count, destinationIndexPath.item < items.count else { return }
        let moved = items.remove(at: sourceIndexPath.item)
        items.insert(moved, at: destinationIndexPath.item)
        arrangeItems = items
    }

    /// Keeps purged items pinned at the tail by clamping any drop target to the last
    /// available slot.
    func collectionView(_ collectionView: UICollectionView,
                        targetIndexPathForMoveFromItemAt originalIndexPath: IndexPath,
                        toProposedIndexPath proposedIndexPath: IndexPath) -> IndexPath {
        let maxIndex = max(0, availableCount - 1)
        if proposedIndexPath.item > maxIndex {
            return IndexPath(item: maxIndex, section: proposedIndexPath.section)
        }
        return proposedIndexPath
    }
}
