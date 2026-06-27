// ImageViewController+Focus.swift
import UIKit
import os.log

// MARK: - Focus Handling & Preloading

extension ImageViewController {

    func indexPathForPreferredFocusedView(in collectionView: UICollectionView) -> IndexPath? {
        // Simple: focus on current index if valid, otherwise first item
        if dataSource.currentIndex < dataSource.count {
            return IndexPath(item: dataSource.currentIndex, section: 0)
        } else if !dataSource.isEmpty {
            return IndexPath(item: 0, section: 0)
        }
        return nil
    }

    override var preferredFocusEnvironments: [UIFocusEnvironment] {
        if isInGridMode && !dataSource.isEmpty {
            // If we have a selected cell, prefer to focus on it
            if let selectedIndexPath = simpleSelectionManager.currentSelection,
               let selectedCell = gridView.cellForItem(at: selectedIndexPath) {
                return [selectedCell]
            }
            return [gridView]
        } else if !isInGridMode {
            return [imageView]
        }
        return super.preferredFocusEnvironments
    }

    override func didUpdateFocus(in context: UIFocusUpdateContext, with coordinator: UIFocusAnimationCoordinator) {
        super.didUpdateFocus(in: context, with: coordinator)

        // Debug logging for sound investigation
        logger.debug("🔊 [FOCUS] Focus change detected - from: \(String(describing: context.previouslyFocusedItem)) to: \(String(describing: context.nextFocusedItem))")

        // Only handle grid focus changes
        guard isInGridMode,
              gridView.alpha == 1,  // Don't interfere during transitions
              let nextCell = context.nextFocusedItem as? UICollectionViewCell,
              let nextIndexPath = gridView.indexPath(for: nextCell) else {
            return
        }

        // Album sections are read-only: track which album item is focused (so a SELECT
        // press opens the right one) but never touch the library's selection/index.
        if nextIndexPath.section != ImageViewController.librarySectionIndex {
            albumCurrentAlbumIndex = nextIndexPath.section - 1
            albumCurrentItemIndex = nextIndexPath.item
            rememberAlbumCursor()
            return
        }

        // CRITICAL FIX FOR MOVE MODE: Handle selection differently in move mode
        if isMoveMode {
            logger.debug("🔊 [FOCUS] In move mode - handling focus change specially")

            // Get the previously focused cell's index path
            if let previousCell = context.previouslyFocusedItem as? UICollectionViewCell,
               let previousIndexPath = gridView.indexPath(for: previousCell) {

                // If the previously focused cell was our moving item, update its position
                if previousIndexPath == movingItemIndexPath {
                    // Update the moving item's index path to the new position
                    movingItemIndexPath = nextIndexPath
                    movingItemIndex = nextIndexPath.item

                    // Clear selection from the old cell
                    if let oldCell = previousCell as? ImageThumbnailCell {
                        oldCell.isSelected = false
                        oldCell.updateVisualEffects()
                    }

                    // Apply selection to the new cell
                    if let newCell = nextCell as? ImageThumbnailCell {
                        newCell.isSelected = true
                        newCell.updateVisualEffects()
                    }

                    logger.debug("🔊 [FOCUS] Updated moving item position to index: \(nextIndexPath.item)")
                }
            }

            // Don't update SimpleSelectionManager in move mode
            return
        }

        // NORMAL MODE: Handle selection normally when not in move mode

        // CRITICAL: If we already have a selection that matches the focused item, don't change it
        // This prevents interference during grid view transitions
        if let currentSelection = simpleSelectionManager.currentSelection,
           currentSelection == nextIndexPath {
            logger.debug("🔊 [FOCUS] Focus matches current selection (\(nextIndexPath.item)) - no action needed")
            return
        }

        logger.debug("🔊 [FOCUS] Grid focus change to index: \(nextIndexPath.item)")

        // Cancel any pending focus debounce timer
        focusDebounceTimer?.invalidate()

        // CRITICAL: Clear the previous selection immediately to prevent dual blue strokes
        // This ensures only one blue outline is visible at any time
        if let currentSelection = simpleSelectionManager.currentSelection,
           currentSelection != nextIndexPath {
            // Immediately clear the previous selection's visual state
            if let previousCell = gridView.cellForItem(at: currentSelection) as? ImageThumbnailCell {
                previousCell.isSelected = false
                gridView.deselectItem(at: currentSelection, animated: false)
            }
        }

        // CRITICAL: Let the selection manager handle ALL selection logic
        // Do NOT manually manipulate cell selection states here to prevent race conditions
        focusDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.03, repeats: false) { [weak self] _ in
            guard let self = self else { return }

            // CRITICAL: Synchronize data source with visual selection
            self.dataSource.setCurrentIndex(nextIndexPath.item)

            // The selection manager will properly clear previous selections and set new ones
            self.simpleSelectionManager.selectItem(at: nextIndexPath)

            self.logger.debug("🔄 [SYNC] Focus change synchronized - visual: \(nextIndexPath.item), data: \(self.dataSource.currentIndex)")

            // Preload the currently focused item for smooth transitions
            self.preloadFocusedItem(at: nextIndexPath.item)
        }
    }

    override func shouldUpdateFocus(in context: UIFocusUpdateContext) -> Bool {
        logger.debug("🎯 [FOCUS] shouldUpdateFocus called")
        logger.debug("🎯 [FOCUS] Current state - currentIndex: \(self.dataSource.currentIndex)")
        return super.shouldUpdateFocus(in: context)
    }

    // MARK: - Preloading

    private func preloadFocusedItem(at index: Int) {
        guard let path = dataSource.getPath(at: index) else { return }

        let mediaItem = MediaItem(path: path)

        // Preload images in background for smooth transitions
        Task {
            if mediaItem.isVideo {
                // For videos, ensure the thumbnail is cached via the shared pipeline
                let cellSize = CGSize(width: 400, height: 225) // Reasonable size for caching
                _ = await VideoThumbnailCache.shared.getThumbnailAsync(for: mediaItem.path, targetSize: cellSize)
            } else {
                // For images, preload the full-size image
                _ = await AsyncImageLoader.shared.loadImage(from: mediaItem.path, targetSize: self.view.bounds.size)
            }
        }
    }
}
