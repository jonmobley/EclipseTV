// ImageViewController+CollectionView.swift
import UIKit
import AVFoundation
import os.log

// MARK: - UICollectionViewDataSource & UICollectionViewDelegate
extension ImageViewController: UICollectionViewDataSource, UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        let count = dataSource.count
        logger.info("📊 [COLLECTION] numberOfItems=\(count)")
        return count
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        return PerformanceMonitor.shared.measureUIOperation("cellForItemAt") {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "ThumbnailCell", for: indexPath) as! ImageThumbnailCell
            
            guard let path = dataSource.getPath(at: indexPath.item) else {
                logger.warning("Invalid index: \(indexPath.item), max: \(self.dataSource.count - 1)")
                return cell
            }
            
            let mediaItem = MediaItem(path: path)
            logger.debug("🧩 [CELL] Configuring index=\(indexPath.item) file=\(mediaItem.fileName) isVideo=\(mediaItem.isVideo)")
            
            // Configure cell with media item
            configureThumbnailCell(cell, with: mediaItem, at: indexPath)
            
            // CRITICAL FIX: Set the selected state based on move mode
            if isMoveMode && indexPath == movingItemIndexPath {
                // This is the item being moved - keep it selected
                cell.isSelected = true
            } else {
                // All other cells should not be selected
                cell.isSelected = false
            }
            
            return cell
        }
    }
    
    private func configureThumbnailCell(_ cell: ImageThumbnailCell, with mediaItem: MediaItem, at indexPath: IndexPath) {
        // Remove any existing long press gestures from previous cell reuse
        cell.gestureRecognizers?.forEach { gesture in
            if gesture is UILongPressGestureRecognizer {
                cell.removeGestureRecognizer(gesture)
            }
        }
        
        // Set cell tag for identification
        cell.tag = indexPath.item
        
        // Configure basic cell state immediately
        if mediaItem.isVideo {
            cell.configure(with: nil, isVideo: true)
        } else {
            cell.configure(with: nil, isVideo: false)
        }
        
        // Add long press gesture recognizer for options menu
        let longPressGesture = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 0.5
        cell.addGestureRecognizer(longPressGesture)
        
        // Load thumbnail asynchronously using the improved configureAsync method
        let cellSize = (gridView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 300, height: 169)
        cell.configureAsync(imagePath: mediaItem.path, isVideo: mediaItem.isVideo, cellSize: cellSize, userPosition: nil)
        
        // Handle video metadata separately if needed
        if mediaItem.isVideo {
            Task {
                // Extract actual video duration asynchronously
                let url = URL(fileURLWithPath: mediaItem.path)
                let duration = await getVideoDuration(for: url)
                let settings = viewModel.getVideoSettings(for: mediaItem)
                
                await MainActor.run {
                    logger.debug("🎛️ [CELL] Updating video meta index=\(indexPath.item) duration=\(duration) loop=\(settings.isLooping) mute=\(settings.isMuted)")
                    // Verify cell is still for the same item before updating
                    if let visibleCell = gridView.cellForItem(at: indexPath) as? ImageThumbnailCell,
                       visibleCell.tag == indexPath.item {
                        // Update video metadata with actual duration - don't wait for thumbnail
                        // Use current image if available, or nil if still loading
                        visibleCell.configure(with: visibleCell.currentImage, isVideo: true, duration: duration, 
                                            isLooping: settings.isLooping, isMuted: settings.isMuted)
                    }
                }
            }
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        dataSource.debugState()
        
        // In move mode, finish the move when selecting an item
        if isMoveMode {
            // If we select the same item we're moving, end move mode
            if indexPath == movingItemIndexPath {
                endMoveMode()
            } else {
                // Otherwise, move the item to the new position
                if let sourceIndex = movingItemIndex {
                    moveItemToPosition(from: sourceIndex, to: indexPath.item)
                    endMoveMode()
                }
            }
            return
        }
        
        // Ignore selection events when ignoring
        if isIgnoringSelectionEvents {
            return
        }
        
        // Go to fullscreen
        if indexPath.item < dataSource.count {
            dataSource.setCurrentIndex(indexPath.item)
            hideGridView() // Use the smooth transition method we just created
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, willDisplay cell: UICollectionViewCell, forItemAt indexPath: IndexPath) {
        // CRITICAL FIX: Ensure proper selection state when cells become visible
        if let thumbnailCell = cell as? ImageThumbnailCell {
            if isMoveMode && indexPath == movingItemIndexPath {
                // This is the item being moved - ensure it stays selected
                thumbnailCell.isSelected = true
                thumbnailCell.updateVisualEffects()
            } else {
                // All other cells should not be selected
                thumbnailCell.isSelected = false
                thumbnailCell.updateVisualEffects()
            }
        }
        
        // Preload images and videos for visible cells and their neighbors
        let preloadRange = 2 // Number of cells to preload on each side
        
        // Get the range of indices to preload
        let startIndex = max(0, indexPath.item - preloadRange)
        let endIndex = min(dataSource.count - 1, indexPath.item + preloadRange)
        
        // Preload video assets around the current index for smooth transitions
        VideoCacheManager.shared.preloadVideosAroundIndex(indexPath.item, in: dataSource)
        
        // Preload thumbnails for the range
        Task {
            for index in startIndex...endIndex {
                guard let path = dataSource.getPath(at: index) else { continue }
                let isVideo = path.lowercased().hasSuffix(".mp4") || path.lowercased().hasSuffix(".mov")
                let cellSize = (collectionView.collectionViewLayout as? UICollectionViewFlowLayout)?.itemSize ?? CGSize(width: 400, height: 225)
                
                if isVideo {
                    _ = await VideoThumbnailCache.shared.getThumbnailAsync(for: path, targetSize: cellSize)
                } else {
                    _ = await AsyncImageLoader.shared.loadImage(from: path, targetSize: cellSize)
                }
            }
        }
    }
    
}

// Helper method to get video duration - non-duplicate helper
private extension ImageViewController {
    func getVideoDuration(for url: URL) async -> TimeInterval {
        let asset = AVURLAsset(url: url)
        do {
            let duration = try await asset.load(.duration)
            return duration.seconds.isFinite ? duration.seconds : 0
        } catch {
            logger.error("Failed to get video duration: \(error)")
            return 0
        }
    }
}
