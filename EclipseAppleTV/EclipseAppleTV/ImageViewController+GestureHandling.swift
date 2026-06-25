import UIKit
import AVFoundation  // Add this import for CMTime and AVPlayer

extension ImageViewController {
    
    func setupGestures() {
        // Back button press for returning to grid
        let backPressRecognizer = UITapGestureRecognizer()
        backPressRecognizer.addTarget(self, action: #selector(handleBackPress))
        backPressRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
        view.addGestureRecognizer(backPressRecognizer)
        
        // Play/Pause button press for toggling grid view
        let playPauseRecognizer = UITapGestureRecognizer()
        playPauseRecognizer.addTarget(self, action: #selector(handlePlayPausePress))
        playPauseRecognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.playPause.rawValue)]
        view.addGestureRecognizer(playPauseRecognizer)
        
        // Swipe gestures for navigating between media in fullscreen
        setupNavigationSwipeGestures()
        
        // Set delegate for all gesture recognizers
        for gestureRecognizer in view.gestureRecognizers ?? [] {
            gestureRecognizer.delegate = self
        }
    }
    
    // MARK: - Navigation Swipe Setup
    
    /// Adds left/right swipe gestures so users can navigate between media in fullscreen.
    /// A deliberate swipe is required, which avoids the accidental sliding that motivated
    /// removing the previous free-form pan gesture.
    private func setupNavigationSwipeGestures() {
        let swipeLeft = UISwipeGestureRecognizer(target: self, action: #selector(handleNavigationSwipe(_:)))
        swipeLeft.direction = .left
        view.addGestureRecognizer(swipeLeft)
        
        let swipeRight = UISwipeGestureRecognizer(target: self, action: #selector(handleNavigationSwipe(_:)))
        swipeRight.direction = .right
        view.addGestureRecognizer(swipeRight)
    }
    
    /// Handles left/right swipes to move between media items in fullscreen image mode.
    @objc private func handleNavigationSwipe(_ gesture: UISwipeGestureRecognizer) {
        guard !isInGridMode && !isVideo else { return }
        
        switch gesture.direction {
        case .left:
            nextImage()
        case .right:
            previousImage()
        default:
            break
        }
    }
    
    // MARK: - Override pressesBegan to handle remote control in move mode
    
    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        // Check if we're in move mode
        if isMoveMode {
            for press in presses {
                guard let key = press.key else { continue }
                
                // Try to handle move mode remote presses
                if handleMoveModeRemotePress(key.keyCode) {
                    return
                }
            }
        }
        
        // Handle right/left clicks in fullscreen mode.
        // Note: Down and Select are intentionally not intercepted for video so
        // AVPlayerViewController can reveal/hide its own transport controls.
        if !isInGridMode {
            for press in presses {
                if press.type == .rightArrow {
                    nextImage()
                    return
                } else if press.type == .leftArrow {
                    previousImage()
                    return
                } else if press.type == .select && !isVideo {
                    // Only handle select for non-video content
                    handleCenterSelectPress()
                    return
                }
            }
        }
        
        // Pass to super if not handled
        super.pressesBegan(presses, with: event)
    }
    
    // MARK: - Gesture Handler Methods
    
    @objc func handlePlayPausePress() {
        if !isInGridMode && isVideo {
            // Toggle video playback
            if let player = playerView.player {
                if player.rate > 0 {
                    player.pause()
                } else {
                    // Get the current media item to check for custom playback rate
                    if let currentPath = dataSource.getCurrentPath() {
                        let mediaItem = MediaItem(path: currentPath)
                        let settings = viewModel.getVideoSettings(for: mediaItem)
                        
                        // Apply custom playback rate if different from 1.0
                        if settings.playbackRate != 1.0 {
                            player.rate = settings.playbackRate
                        } else {
                            player.play()
                        }
                    } else {
                        player.play()
                    }
                }
            }
        } else {
            // Toggle grid view for non-video content
            toggleGridView()
        }
    }
    
    @objc func handleBackPress() {
        logger.debug("Back button pressed")
        
        // First priority: If there's a presented view controller (like a settings menu), dismiss it
        if let presentedVC = self.presentedViewController {
            logger.debug("Dismissing presented view controller")
            presentedVC.dismiss(animated: true) {
                // Process any queued content after dismissing the menu
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                    self?.processQueuedContent()
                }
            }
            return
        }
        
        // Second priority: If in move mode, exit move mode
        if isMoveMode {
            logger.debug("Exiting move mode")
            endMoveMode()
            return
        }
        
        // Third priority: If in fullscreen mode, go back to grid view
        if !isInGridMode {
            // Store the current image index before showing grid (no longer needed with MediaDataSource)
            // self.previouslySelectedIndex = self.currentImageIndex
            
            // Stop video playback if needed
            if isVideo && playerView.player != nil {
                logger.debug("Stopping video playback on back press")
                playerView.player?.pause()
            }
            
            // Log the index we're going to select when returning to grid
            logger.debug("🔄 [NAVIGATION] Returning to grid view, will select image at index: \(self.dataSource.currentIndex)")
            
            // Transition to grid view
            showGridViewTransition()
        } else {
            // If already in grid view, let system handle the back button
            UIApplication.shared.sendAction(#selector(UIApplication.sendEvent(_:)), to: nil, from: nil, for: nil)
        }
    }
    
    @objc func handleCenterSelectPress() {
        logger.debug("Center select button pressed (for non-video content)")
        
        // This method is now only called for non-video content
        // Video playback is handled by AVPlayerViewController's built-in remote control
        guard !isInGridMode && !isVideo else { 
            logger.debug("Ignoring center select - not applicable (isInGridMode: \(self.isInGridMode), isVideo: \(self.isVideo))")
            return 
        }
        
        // Handle center select for images or other non-video content
        logger.debug("Center select pressed on image - could implement image-specific actions here")
    }
    
    // MARK: - UIGestureRecognizerDelegate
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // Allow navigation swipes only in fullscreen image mode
        if gestureRecognizer is UISwipeGestureRecognizer {
            return !isInGridMode && !isVideo
        }
        
        // Disable zoom/pinch gestures completely (iOS only)
        #if !os(tvOS)
        if gestureRecognizer is UIPinchGestureRecognizer {
            return false
        }
        #endif
        
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, canBePreventedByGestureRecognizer preventingGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Don't let any other gesture recognizers prevent our button press recognizers
        if gestureRecognizer is UITapGestureRecognizer && 
           ((gestureRecognizer.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.menu.rawValue))) ||
            (gestureRecognizer.allowedPressTypes.contains(NSNumber(value: UIPress.PressType.playPause.rawValue)))) {
            return false
        }
        return true
    }
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, canPreventGestureRecognizer preventedGestureRecognizer: UIGestureRecognizer) -> Bool {
        // Prevent any pan gestures (which would be from the remote touch surface)
        if preventedGestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        
        return false
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Allow navigation swipes only in fullscreen image mode
        if gestureRecognizer is UISwipeGestureRecognizer {
            return !isInGridMode && !isVideo
        }
        
        // Prevent zoom/pinch gestures from beginning (iOS only)
        #if !os(tvOS)
        if gestureRecognizer is UIPinchGestureRecognizer {
            return false
        }
        #endif
        
        // Allow pan gestures on player view when video is paused
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           panGesture.view == playerView.view,
           isVideo,
           let player = playerView.player,
           player.rate == 0 {  // Check if player is paused
            return true
        }
        
        // Prevent pan gestures that aren't explicitly for our UI
        if gestureRecognizer is UIPanGestureRecognizer && 
           gestureRecognizer.view == self.view {
            return false
        }
        
        return true
    }

    // Setup player view gestures - now minimal to let AVPlayerViewController handle most interactions
    func setupPlayerViewGestures() {
        // Let AVPlayerViewController handle most gestures including play/pause
        // We only add custom gestures if absolutely necessary
        
        // Note: Removed custom tap and pan gestures to avoid conflicts with AVPlayerViewController's
        // built-in remote control handling. The AVPlayerViewController should handle:
        // - Play/pause via center button
        // - Scrubbing via touch surface
        // - Transport controls
        
        logger.debug("Player view gestures setup - using AVPlayerViewController defaults")
    }

    // Removed handlePlayerSingleTap and handlePlayerDoubleTap methods
    // These are now handled by AVPlayerViewController's built-in remote control support
    
    // Removed handlePlayerPan method - scrubbing is now handled by AVPlayerViewController's built-in support
    
    /// Updates the on-screen time display for the given player
    private func updateTimeDisplay(for player: AVPlayer) {
        guard let item = player.currentItem, item.duration.isValid else {
            return
        }
        
        // AVPlayerViewController already shows time, but we can enhance it if needed
        // This method is a placeholder for any custom time display you might want to add
        
        // Force update of transport controls
        playerView.updateViewConstraints()
    }
    
    // MARK: - tvOS Feedback Handling
    
    // Since UISelectionFeedbackGenerator is not available on tvOS, we'll use a simpler approach
    // These methods provide a way to implement platform-specific feedback in the future
    
    private func prepareFeedback() {
        // For tvOS, this is a no-op, but could be extended for custom feedback
        // on future platforms or via external accessories
    }
    
    private func provideFeedback() {
        // For tvOS, we could implement visual feedback instead
        // or handle custom accessories that might provide haptic feedback
        
        // For now, we'll just log for debugging
        logger.debug("Feedback would be provided here")
    }
    
    private func cleanupFeedback() {
        // Clean up any resources related to feedback
    }
    
}
