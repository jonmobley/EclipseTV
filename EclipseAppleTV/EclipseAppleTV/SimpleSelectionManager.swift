import UIKit

class SimpleSelectionManager {
    private weak var collectionView: UICollectionView?
    private var selectedIndexPath: IndexPath?
    
    init(collectionView: UICollectionView) {
        self.collectionView = collectionView
        
        // Configure for reliable single selection
        collectionView.allowsSelection = true
        collectionView.allowsMultipleSelection = false
    }
    
    func selectItem(at indexPath: IndexPath) {
        guard let collectionView = collectionView else { return }
        
        // Only change if different
        guard selectedIndexPath != indexPath else { return }
        
        // CRITICAL: Clear ALL visible cell selections first to prevent multiple blue strokes
        clearAllVisibleSelections()
        
        // Clear old selection from collection view
        if let previous = selectedIndexPath {
            collectionView.deselectItem(at: previous, animated: false)
        }
        
        // Set new selection immediately to prevent race conditions
        selectedIndexPath = indexPath
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
        
        // Apply visual effects to new cell immediately, not in animation
        if let newCell = collectionView.cellForItem(at: indexPath) as? ImageThumbnailCell {
            newCell.isSelected = true
            // Force immediate update to prevent dual strokes during rapid navigation
            newCell.setNeedsLayout()
            newCell.layoutIfNeeded()
        }
        
        // Validate selection state is consistent after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.validateSelectionState()
        }
    }
    
    var currentSelection: IndexPath? {
        return selectedIndexPath
    }
    
    func clearSelection() {
        if let selected = selectedIndexPath {
            collectionView?.deselectItem(at: selected, animated: false)
            selectedIndexPath = nil
        }
        // Also clear all visible selections to be safe
        clearAllVisibleSelections()
    }
    
    // MARK: - Private Helper Methods
    
    /// Clears selection state from all visible cells to prevent multiple blue strokes
    private func clearAllVisibleSelections() {
        guard let collectionView = collectionView else { return }
        
        // Force immediate clearing of all visible cell selections
        for cell in collectionView.visibleCells {
            if let thumbnailCell = cell as? ImageThumbnailCell {
                thumbnailCell.isSelected = false
                // Force immediate visual update to prevent lingering blue strokes
                thumbnailCell.setNeedsLayout()
                thumbnailCell.layoutIfNeeded()
            }
        }
        
        // Also clear any collection view selections that might be lingering
        if let selectedItems = collectionView.indexPathsForSelectedItems {
            for indexPath in selectedItems {
                collectionView.deselectItem(at: indexPath, animated: false)
            }
        }
    }
    
    /// Validates that selection state is consistent across all visible cells
    func validateSelectionState() {
        guard let collectionView = collectionView else { return }
        
        for cell in collectionView.visibleCells {
            if let thumbnailCell = cell as? ImageThumbnailCell {
                let indexPath = collectionView.indexPath(for: cell)
                let shouldBeSelected = indexPath == selectedIndexPath
                
                if thumbnailCell.isSelected != shouldBeSelected {
                    thumbnailCell.isSelected = shouldBeSelected
                }
            }
        }
    }
    
    /// Synchronizes the selection manager's internal state with an external current index
    /// This is useful when the current index changes outside of the selection manager (e.g., fullscreen navigation)
    func synchronizeSelectionWith(currentIndex: Int) {
        guard let collectionView = collectionView else { return }
        
        let newIndexPath = IndexPath(item: currentIndex, section: 0)
        
        // Only update if the selection is actually different
        guard selectedIndexPath != newIndexPath else { return }
        
        // Clear all selections first
        clearAllVisibleSelections()
        
        // Clear old collection view selection
        if let previous = selectedIndexPath {
            collectionView.deselectItem(at: previous, animated: false)
        }
        
        // Update internal state
        selectedIndexPath = newIndexPath
        
        // Apply new selection to collection view
        collectionView.selectItem(at: newIndexPath, animated: false, scrollPosition: [])
        
        // Apply visual state to the cell if it's visible
        if let cell = collectionView.cellForItem(at: newIndexPath) as? ImageThumbnailCell {
            cell.isSelected = true
            cell.setNeedsLayout()
            cell.layoutIfNeeded()
        }
    }
} 