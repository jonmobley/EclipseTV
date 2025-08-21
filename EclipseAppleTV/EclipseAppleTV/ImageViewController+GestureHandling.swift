import UIKit
import AVFoundation  // Add this import for CMTime and AVPlayer

extension ImageViewController {
    
    func setupGestures() {
        // We're removing the swipe gestures to prevent accidental sliding
        // Navigation will be handled exclusively through directional button presses
        
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
        
        // Set up image pan gesture for positioning
        setupImagePanGesture()
        
        // Set delegate for all gesture recognizers to prevent default swiping behavior
        for gestureRecognizer in view.gestureRecognizers ?? [] {
            gestureRecognizer.delegate = self
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
        
        // Handle right/left/down clicks in fullscreen mode
        // Note: Removed select button handling to let AVPlayerViewController handle it naturally
        if !isInGridMode {
            for press in presses {
                if press.type == .rightArrow {
                    nextImage()
                    return
                } else if press.type == .leftArrow {
                    previousImage()
                    return
                } else if press.type == .downArrow {
                    handleDownPress()
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
    
    @objc func handleDownPress() {
        logger.debug("Down button pressed")
        
        // Only handle down press for video content in fullscreen mode
        guard !isInGridMode && isVideo else { return }
        
        // Toggle player controls visibility
        togglePlayerControls()
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
        // Disable swipe gestures completely
        if gestureRecognizer is UISwipeGestureRecognizer {
            return false
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
        // Our button press recognizers should prevent swipe gestures
        if gestureRecognizer is UITapGestureRecognizer && preventedGestureRecognizer is UISwipeGestureRecognizer {
            return true
        }
        
        // Prevent any pan gestures (which would be from the remote touch surface)
        if preventedGestureRecognizer is UIPanGestureRecognizer {
            return true
        }
        
        return false
    }
    
    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        // Prevent swipe gestures from beginning
        if gestureRecognizer is UISwipeGestureRecognizer {
            return false
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
        
        // Allow our image pan gesture for positioning
        if let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
           panGesture == imagePanGesture,
           !isInGridMode && !isVideo {
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
        guard let item = player.currentItem, 
              let duration = item.duration.isValid ? item.duration : nil else {
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
    
    // MARK: - Image Pan Gesture Setup
    
    /// Sets up pan gesture for image positioning
    private func setupImagePanGesture() {
        // Remove existing gesture if any
        if let existingGesture = imagePanGesture {
            imageView.removeGestureRecognizer(existingGesture)
        }
        
        // Create new pan gesture for image positioning
        let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleImagePan(_:)))
        panGesture.delegate = self
        imagePanGesture = panGesture
        imageView.addGestureRecognizer(panGesture)
        imageView.isUserInteractionEnabled = true
    }
    
    /// Handles pan gestures for image positioning
    @objc private func handleImagePan(_ gesture: UIPanGestureRecognizer) {
        guard !isInGridMode && !isVideo,
              let currentPath = dataSource.getCurrentPath() else { return }
        
        switch gesture.state {
        case .began:
            // Store initial position if not already stored
            if imagePositions[currentPath] == nil {
                imagePositions[currentPath] = .zero
            }
            
        case .changed:
            let translation = gesture.translation(in: view)
            
            // Get or create current position for this image
            var currentPosition = imagePositions[currentPath] ?? .zero
            
            // Update position with translation
            currentPosition.x += translation.x
            currentPosition.y += translation.y
            
            // Apply reasonable bounds to prevent moving too far off-screen
            let maxOffset: CGFloat = 200
            currentPosition.x = max(-maxOffset, min(maxOffset, currentPosition.x))
            currentPosition.y = max(-maxOffset, min(maxOffset, currentPosition.y))
            
            // Store updated position
            imagePositions[currentPath] = currentPosition
            
            // Apply the transform to the image view
            imageView.transform = CGAffineTransform(translationX: currentPosition.x, y: currentPosition.y)
            
            // Reset gesture translation to prevent accumulation
            gesture.setTranslation(.zero, in: view)
            
        case .ended, .cancelled, .failed:
            // Position is already stored, nothing more to do
            break
            
        default:
            break
        }
    }
    
    // MARK: - Player Controls Management
    
    /// Toggles the visibility of video player controls
    private func togglePlayerControls() {
        guard isVideo else { return }
        
        let shouldShow = !playerView.showsPlaybackControls
        
        // Defer the controls change to avoid constraint conflicts during focus transitions
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            // Double-check we're still in video mode
            guard self.isVideo else { return }
            
            self.playerView.showsPlaybackControls = shouldShow
            self.logger.debug("Player controls \(shouldShow ? "shown" : "hidden")")
            
            // If showing controls, auto-hide them after 5 seconds unless video is paused
            if shouldShow {
                // Cancel any existing auto-hide timer
                self.playerControlsAutoHideTimer?.invalidate()
                
                // Only auto-hide if video is playing
                if let player = self.playerView.player, player.rate > 0 {
                    self.playerControlsAutoHideTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: false) { [weak self] _ in
                        self?.hidePlayerControlsIfPlaying()
                    }
                }
            } else {
                // Cancel auto-hide timer when manually hiding
                self.playerControlsAutoHideTimer?.invalidate()
            }
        }
    }
    
    /// Hides player controls if video is currently playing
    private func hidePlayerControlsIfPlaying() {
        guard isVideo, let player = playerView.player else { return }
        
        // Only hide if video is still playing
        if player.rate > 0 {
            // Defer the controls change to avoid constraint conflicts
            DispatchQueue.main.async { [weak self] in
                guard let self = self, self.isVideo else { return }
                self.playerView.showsPlaybackControls = false
                self.logger.debug("Player controls auto-hidden")
            }
        }
    }
}
