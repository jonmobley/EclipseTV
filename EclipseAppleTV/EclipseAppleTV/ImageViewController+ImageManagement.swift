// ImageViewController+ImageManagement.swift
import UIKit
import AVFoundation
import AVKit

// Use the app module name to fully qualify the class
extension ImageViewController {
    
    /// Displays the image at the current index
    internal func displayImageAtCurrentIndex() {
        guard let currentPath = currentDisplayPath() else {
            ErrorHandler.shared.handle(.emptyLibrary, context: "displayImageAtCurrentIndex")
            return
        }
        
        let currentItem = MediaItem(path: currentPath)
        
        PerformanceMonitor.shared.measureUIOperation("displayImageAtCurrentIndex") {
            // Only show activity indicator during initial load
            if dataSource.isEmpty {
                activityIndicator.startAnimating()
            }
            hideInstructions()
            
            if currentItem.isVideo {
                displayVideo(currentItem)
            } else {
                displayImage(currentItem)
            }
        }
    }
    
    /// Displays the image at the current index with smooth transition coordination
    private func displayImageAtCurrentIndexWithTransition() {
        guard let currentPath = currentDisplayPath() else {
            logger.error("❌ [DISPLAY] No current path available for displayImageAtCurrentIndexWithTransition")
            ErrorHandler.shared.handle(.emptyLibrary, context: "displayImageAtCurrentIndexWithTransition")
            return
        }
        
        logger.info("🖼️ [DISPLAY] Starting displayImageAtCurrentIndexWithTransition for path: \(currentPath)")
        let currentItem = MediaItem(path: currentPath)
        logger.debug("🖼️ [DISPLAY] Media item created - isVideo: \(currentItem.isVideo), fileName: \(currentItem.fileName)")
        
        PerformanceMonitor.shared.measureUIOperation("displayImageAtCurrentIndexWithTransition") {
            hideInstructions()
            
            if currentItem.isVideo {
                logger.info("🎬 [DISPLAY] Displaying video: \(currentItem.fileName)")
                displayVideoWithTransition(currentItem)
            } else {
                logger.info("🖼️ [DISPLAY] Displaying image: \(currentItem.fileName)")
                displayImageWithTransition(currentItem)
            }
        }
    }
    
    private func displayImage(_ mediaItem: MediaItem) {
        logger.info("Displaying image: \(mediaItem.fileName)")
        
        Task { @MainActor in
            // Load full-size image
            let image = await AsyncImageLoader.shared.loadImage(from: mediaItem.path, targetSize: self.view.bounds.size)
            
            await MainActor.run {
                if let image = image {
                    self.imageView.image = image
                    self.imageView.isHidden = false
                    self.playerView.view.isHidden = true
                    self.isVideo = false

                    // Switched to a photo: stop streaming playback state to companions.
                    self.removePlaybackStatusObserver()
                    self.broadcastPlaybackStopped()

                    // Apply stored position for this image
                    self.applyStoredImagePosition(for: mediaItem.path)
                } else {
                    ErrorHandler.shared.handle(.fileNotFound(path: mediaItem.path), context: "displayImage")
                }
                
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    private func displayImageWithTransition(_ mediaItem: MediaItem) {
        Task {
            let fullSizeImage = await AsyncImageLoader.shared.loadImage(from: mediaItem.path, targetSize: self.view.bounds.size)
            DispatchQueue.main.async { [self] in
                if let image = fullSizeImage {
                    self.imageView.isHidden = false
                    self.imageView.image = image
                    self.imageView.alpha = 0
                    
                    // Apply stored position for this image
                    self.applyStoredImagePosition(for: mediaItem.path)
                    
                    UIView.animate(withDuration: 0.5, delay: 0, options: [.curveEaseOut]) {
                        self.imageView.alpha = 1
                    } completion: { (finished: Bool) in
                        // self.activityIndicator.stopAnimating()  // Hidden per user request
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()
                    }
                } else {
                    self.logger.error("❌ [IMAGE-TRANSITION] Failed to load image, going back to grid view")
                    // self.activityIndicator.stopAnimating()  // Hidden per user request
                    ErrorHandler.shared.handle(.fileNotFound(path: mediaItem.path), context: "displayImageWithTransition")
                    self.showGridView()
                }
            }
        }
    }
    
    /// Displays the media at the current index with a smooth dissolve transition
    private func displayImageAtCurrentIndexWithDissolveTransition() {
        guard let currentPath = currentDisplayPath() else {
            logger.error("❌ [DISSOLVE] No current path available")
            ErrorHandler.shared.handle(.emptyLibrary, context: "displayImageAtCurrentIndexWithDissolveTransition")
            return
        }
        
        logger.info("🔄 [DISSOLVE] Starting dissolve transition for: \(URL(fileURLWithPath: currentPath).lastPathComponent)")

        let currentItem = MediaItem(path: currentPath)
        
        PerformanceMonitor.shared.measureUIOperation("displayImageAtCurrentIndexWithDissolveTransition") {
            if currentItem.isVideo {
                displayVideoWithDissolveTransition(currentItem)
            } else {
                displayImageWithDissolveTransition(currentItem)
            }
        }
    }
    
    /// Displays an image with a smooth dissolve transition from current content
    private func displayImageWithDissolveTransition(_ mediaItem: MediaItem) {
        logger.info("🖼️ [DISSOLVE] Transitioning to image: \(mediaItem.fileName)")
        
        Task {
            let fullSizeImage = await AsyncImageLoader.shared.loadImage(from: mediaItem.path, targetSize: self.view.bounds.size)
            
            await MainActor.run {
                guard let image = fullSizeImage else {
                    self.logger.error("❌ [DISSOLVE] Failed to load image")
                    ErrorHandler.shared.handle(.fileNotFound(path: mediaItem.path), context: "displayImageWithDissolveTransition")
                    return
                }
                
                // Stop current video if playing
                if self.isVideo {
                    self.playerView.player?.pause()
                    self.cleanupPlayerLooper()
                }
                
                // Create temp image view for smooth transition
                let tempImageView = UIImageView(image: image)
                tempImageView.contentMode = .scaleAspectFill
                tempImageView.clipsToBounds = true
                tempImageView.frame = self.view.bounds
                tempImageView.alpha = 0
                self.view.addSubview(tempImageView)
                
                // Dissolve transition
                UIView.animate(withDuration: 0.4, animations: {
                    // Fade out current content
                    self.imageView.alpha = 0
                    self.playerView.view.alpha = 0
                    // Fade in new image
                    tempImageView.alpha = 1
                }) { _ in
                                    // Update main image view
                self.imageView.image = image
                self.imageView.alpha = 1
                self.imageView.isHidden = false
                self.isVideo = false
                
                // Apply stored position for this image
                self.applyStoredImagePosition(for: mediaItem.path)
                    
                    // Hide video player
                    self.playerView.view.isHidden = true
                    self.playerView.player = nil
                    
                    // Remove temp view
                    tempImageView.removeFromSuperview()
                    
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }
        }
    }
    
    /// Removes an image from the recent images list
    /// - Parameter path: The path of the image to remove
    internal func removeImageFromRecents(path: String) {
        // Find the index in data source
        for index in 0..<dataSource.count {
            if dataSource.getPath(at: index) == path {
                dataSource.removeMedia(at: index)
                break
            }
        }
    }
    
    /// Moves to the next item in the active collection (library or album)
    internal func nextImage() {
        guard !isInGridMode else { return }

        if advanceDisplayIndex() {
            // Video preloading is only wired for the local library data source.
            if activeCollection == .library {
                VideoCacheManager.shared.preloadVideosAroundIndex(dataSource.currentIndex, in: dataSource)
            }
            displayImageAtCurrentIndexWithDissolveTransition()
        } else {
            logger.debug("📍 [NAVIGATION] nextImage() - already at last item")
        }
    }

    /// Moves to the previous item in the active collection (library or album)
    internal func previousImage() {
        guard !isInGridMode else { return }

        if retreatDisplayIndex() {
            if activeCollection == .library {
                VideoCacheManager.shared.preloadVideosAroundIndex(dataSource.currentIndex, in: dataSource)
            }
            displayImageAtCurrentIndexWithDissolveTransition()
        } else {
            logger.debug("📍 [NAVIGATION] previousImage() - already at first item")
        }
    }
    
    /// Hides the grid view and shows the fullscreen content with smooth animation
    internal func hideGridView() {
        guard isInGridMode else { 
            logger.warning("⚠️ [GRID→FULLSCREEN] Already in fullscreen mode, ignoring hideGridView request")
            return 
        }
        
        logger.info("🔄 [GRID→FULLSCREEN] Hiding grid view")
        logger.debug("🔄 [GRID→FULLSCREEN] Current data source index: \(self.dataSource.currentIndex), path: \(self.dataSource.getCurrentPath() ?? "nil")")
        logger.debug("🔄 [GRID→FULLSCREEN] ImageView current state - isHidden: \(self.imageView.isHidden), alpha: \(self.imageView.alpha), image: \(self.imageView.image != nil ? "present" : "nil")")
        logger.debug("🔄 [GRID→FULLSCREEN] PlayerView current state - isHidden: \(self.playerView.view.isHidden), alpha: \(self.playerView.view.alpha)")
        
        isInGridMode = false
        
        // Start loading content immediately
        // activityIndicator.startAnimating()  // Hidden per user request
        logger.debug("🔄 [GRID→FULLSCREEN] Calling displayImageAtCurrentIndexWithTransition")
        displayImageAtCurrentIndexWithTransition()
        
        // Ensure fullscreen content will appear on top when it fades in
        view.bringSubviewToFront(imageView)
        view.bringSubviewToFront(playerView.view)
        view.bringSubviewToFront(activityIndicator)
        
        // Simultaneously fade out the grid view
        UIView.animate(withDuration: 0.3, animations: { 
            self.gridView.alpha = 0
            self.titleLabel.alpha = 0
            self.gradientView.alpha = 0
        }) { (_: Bool) in
            // Once grid is faded out, hide it
            self.gridView.isHidden = true
            self.titleLabel.isHidden = true
            self.gradientView.isHidden = true
            
            // Reset alpha for when we return to grid
            self.gridView.alpha = 1
            self.titleLabel.alpha = 1
            self.gradientView.alpha = 1
            
            self.logger.debug("🔄 [GRID→FULLSCREEN] Grid view fade out animation completed")
        }
    }
    
    /// Shows the grid view and hides the fullscreen content with smooth animation
    internal func showGridView() {
        guard !isInGridMode else { return }

        // Grid selection/focus is library-driven; album viewing is re-entered on tap.
        activeCollection = .library

        logger.info("🔄 [FULLSCREEN→GRID] Transitioning from fullscreen to grid view")
        
        // Stop activity indicator
        activityIndicator.stopAnimating()
        
        // Stop and clean up video playback first
        if isVideo {
            logger.debug("🔄 [FULLSCREEN→GRID] Stopping video playback")
            if let currentPlayer = playerView.player {
                currentPlayer.pause()
                resourceManager.removeNotificationObserver(for: .AVPlayerItemDidPlayToEndTime, object: currentPlayer.currentItem)
                resourceManager.removePlayerObservers(for: currentPlayer)
            }
            
            cleanupPlayerLooper()
        }

        // The live video is no longer playing fullscreen: stop streaming its position and
        // tell companions it's paused so their scrubber settles.
        removePlaybackStatusObserver()
        broadcastPlaybackStopped()
        
        // Bring fullscreen content to front during transition so it fades out on top
        view.bringSubviewToFront(imageView)
        if isVideo {
            view.bringSubviewToFront(playerView.view)
        }
        
        // Store the current index to synchronize with BEFORE any UI changes
        let targetIndex = dataSource.currentIndex
        
        // Debug current data source state before synchronization
        logger.debug("📍 [GRID-PREPARATION] Data source state before sync - currentIndex: \(targetIndex), path: \(self.dataSource.getCurrentPath() ?? "nil")")
        
        // Prepare grid view for fade-in (set initial state behind fullscreen content)
        gridView.alpha = 0
        titleLabel.alpha = 0
        gradientView.alpha = 0
        gridView.isHidden = false
        titleLabel.isHidden = false
        gradientView.isHidden = false
        
        // CRITICAL: Disable grid mode temporarily to prevent any focus-based selection changes
        isInGridMode = false
        
        // Reload grid data
        gridView.reloadData()
        
        // CRITICAL: Set selection immediately after reload, while grid mode is disabled
        if !dataSource.isEmpty && targetIndex < dataSource.count {
            logger.debug("🔄 [FULLSCREEN→GRID] Setting selection to target index: \(targetIndex) with grid mode disabled")
            let targetIndexPath = IndexPath(item: targetIndex, section: 0)
            
            // Clear any existing selections first
            simpleSelectionManager.clearSelection()
            
            // Set the new selection directly on both the collection view and selection manager
            gridView.selectItem(at: targetIndexPath, animated: false, scrollPosition: [])
            simpleSelectionManager.selectItem(at: targetIndexPath)
            
            // Force immediate layout to apply changes
            gridView.layoutIfNeeded()
        } else {
            logger.debug("🔄 [FULLSCREEN→GRID] Clearing selection - no valid target index")
            simpleSelectionManager.clearSelection()
        }
        
        // Simultaneous smooth animations - fade out fullscreen content and fade in grid
        UIView.animate(withDuration: 0.3, animations: { 
            // Fade out fullscreen content
            self.imageView.alpha = 0
            self.playerView.view.alpha = 0
            
            // Fade in grid content
            self.gridView.alpha = 1
            self.titleLabel.alpha = 1
            self.gradientView.alpha = 1
        }) { (_: Bool) in
            // After animation completes, hide fullscreen views and clean up
            self.imageView.isHidden = true
            self.playerView.view.isHidden = true
            
            // Reset alpha values for fullscreen content for next time
            self.imageView.alpha = 1
            self.playerView.view.alpha = 1
            
            // Bring grid view back to front now that transition is complete
            self.view.bringSubviewToFront(self.gridView)
            self.view.bringSubviewToFront(self.titleLabel)
            self.view.bringSubviewToFront(self.activityIndicator)
            self.view.bringSubviewToFront(self.toastView)
            
            // CRITICAL: Re-enable grid mode now that transition is complete and selection is set
            self.isInGridMode = true
            
            // Force focus update to the selected cell 
            self.setNeedsFocusUpdate()
            self.updateFocusIfNeeded()
            
            // Additional force focus update to ensure proper focus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                if self.isInGridMode {  // Double-check we're still in grid mode
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
            }
            
            self.logger.debug("🔄 [FULLSCREEN→GRID] Grid view transition completed, grid mode enabled")
        }
    }
    
    // MARK: - Image Positioning
    
    /// Resets the image transform so every image is shown centered.
    /// Image repositioning was removed in favor of swipe-to-navigate, so any
    /// previously stored offsets must no longer shift the displayed image.
    private func applyStoredImagePosition(for imagePath: String) {
        imageView.transform = .identity
    }
}
