// ImageViewController+ImageManagement.swift
import UIKit
import AVFoundation
import AVKit

// Use the app module name to fully qualify the class
extension ImageViewController {
    
    /// Displays the most recently used image
    internal func displayMostRecentImage() {
        guard !dataSource.isEmpty else {
            logger.warning("Attempted to display most recent image but no images exist")
            showInstructions()
            return
        }
        
        dataSource.setCurrentIndex(0) // Most recent is at index 0
        displayImageAtCurrentIndex()
    }
    
    /// Displays the image at the current index
    internal func displayImageAtCurrentIndex() {
        guard let currentPath = dataSource.getCurrentPath() else {
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
        guard let currentPath = dataSource.getCurrentPath() else {
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
    
    private func displayVideo(_ mediaItem: MediaItem) {
        logger.info("Displaying video: \(mediaItem.fileName)")
        
        Task { @MainActor in
            // Hide image view and show player
            await MainActor.run {
                self.imageView.isHidden = true
                self.playerView.view.isHidden = false
                self.isVideo = true
            }
            
            // Create player with seamless looping support
            let player = self.setupPlayer(for: mediaItem)
            
            // Set up player
            await MainActor.run {
                // Ensure player view is set up before assigning player
                self.setupPlayerView()
                self.playerView.player = player
                
                // Ensure controls are hidden by default
                self.playerView.showsPlaybackControls = false
                
                // Add observer for playback end
                self.addManagedObserver(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem) { [weak self] _ in
                    self?.handleVideoPlaybackEnd(for: mediaItem)
                }
                
                // Start playback immediately
                player.play()
                self.activityIndicator.stopAnimating()
            }
        }
    }
    
    private func displayVideoWithTransition(_ mediaItem: MediaItem) {
        logger.info("Displaying video with transition: \(mediaItem.fileName)")
        
        Task { @MainActor in
            // Create player with seamless looping support
            let player = self.setupPlayer(for: mediaItem)
            
            await MainActor.run {
                // Hide image view immediately
                self.imageView.isHidden = true
                
                // Set up player
                self.setupPlayerView()
                self.playerView.view.alpha = 0
                self.playerView.view.isHidden = false
                self.playerView.player = player
                self.isVideo = true
                
                // Ensure controls are hidden by default
                self.playerView.showsPlaybackControls = false
                
                // Add observer for playback end
                self.addManagedObserver(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem) { [weak self] _ in
                    self?.handleVideoPlaybackEnd(for: mediaItem)
                }
                
                // Start playback immediately and fade in player
                player.play()
                
                UIView.animate(withDuration: 0.4, animations: { 
                    self.playerView.view.alpha = 1
                }) { (_: Bool) in
                    self.activityIndicator.stopAnimating()
                    self.setNeedsFocusUpdate()
                    self.updateFocusIfNeeded()
                }
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
    
    private func handleVideoPlaybackEnd(for mediaItem: MediaItem) {
        let settings = viewModel.getVideoSettings(for: mediaItem)
        
        if settings.isLooping {
            // Check if AVPlayerLooper failed and fallback to manual looping
            if playerLooper == nil {
                logger.debug("⚡ Fallback to manual seamless loop for: \(mediaItem.fileName)")
                // Use optimized manual looping as fallback
                performOptimizedManualLoop()
            } else {
                logger.debug("Video playback ended - looping handled by AVPlayerLooper")
            }
        } else {
            // Video finished and not looping - could add end-of-video logic here if needed
            logger.debug("Video playback ended - not looping")
        }
    }
    
    /// Performs optimized manual looping with minimal gap
    private func performOptimizedManualLoop() {
        guard let player = playerView.player else { return }
        
        #if DEBUG
        let startTime = CFAbsoluteTimeGetCurrent()
        logger.debug("⚡ [MANUAL-LOOP] Starting manual loop fallback")
        #endif
        
        // Pre-cache the seek to zero
        let seekTime = CMTime.zero
        
        // Use precise seek with tolerance for faster seeking
        player.seek(to: seekTime, toleranceBefore: CMTime.zero, toleranceAfter: CMTime.zero) { [weak self] finished in
            #if DEBUG
            let endTime = CFAbsoluteTimeGetCurrent()
            let seekDuration = (endTime - startTime) * 1000 // Convert to milliseconds
            self?.logger.debug("⚡ [MANUAL-LOOP] Seek completed in \(String(format: "%.2f", seekDuration))ms, success: \(finished)")
            #endif
            
            if finished {
                // Immediately start playback after seek completes
                player.play()
                
                #if DEBUG
                self?.logger.debug("⚡ [MANUAL-LOOP] Playback restarted")
                #endif
            }
        }
    }
    
    #if DEBUG
    /// Adds comprehensive debugging for AVPlayerLooper performance monitoring
    private func addLooperDebugging(for player: AVQueuePlayer, mediaItem: MediaItem) {
        guard let looper = playerLooper else { return }
        
        logger.debug("🔍 [DEBUG] Setting up looper monitoring for: \(mediaItem.fileName)")
        
        // Monitor looper status
        looper.addObserver(self, forKeyPath: "status", options: [.new, .old], context: nil)
        objc_setAssociatedObject(looper, "hasKVOObservers", true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // Monitor player item status for both items
        if let currentItem = player.currentItem {
            currentItem.addObserver(self, forKeyPath: "status", options: [.new, .old], context: nil)
            currentItem.addObserver(self, forKeyPath: "loadedTimeRanges", options: [.new], context: nil)
            currentItem.addObserver(self, forKeyPath: "playbackBufferEmpty", options: [.new], context: nil)
            currentItem.addObserver(self, forKeyPath: "playbackLikelyToKeepUp", options: [.new], context: nil)
            objc_setAssociatedObject(currentItem, "hasKVOObservers", true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        // Monitor queue changes
        player.addObserver(self, forKeyPath: "currentItem", options: [.new, .old], context: nil)
        objc_setAssociatedObject(player, "hasKVOObservers", true, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        // Add time observer for loop detection
        let interval = CMTime(seconds: 0.1, preferredTimescale: CMTimeScale(NSEC_PER_SEC))
        let timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.debugTimeObserver(time: time, player: player, mediaItem: mediaItem)
        }
        
        // Store observer for cleanup
        objc_setAssociatedObject(player, "debugTimeObserver", timeObserver, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        logger.debug("🔍 [DEBUG] Looper monitoring configured")
    }
    
    /// Debug time observer for monitoring playback and loop points
    private func debugTimeObserver(time: CMTime, player: AVQueuePlayer, mediaItem: MediaItem) {
        guard let currentItem = player.currentItem else { return }
        
        let currentTimeSeconds = CMTimeGetSeconds(time)
        let durationSeconds = CMTimeGetSeconds(currentItem.duration)
        
        // Log when approaching end of video (last 0.5 seconds)
        if durationSeconds.isFinite && currentTimeSeconds > (durationSeconds - 0.5) {
            let remaining = durationSeconds - currentTimeSeconds
            logger.debug("🔄 [LOOP-DEBUG] Approaching loop point: \(String(format: "%.3f", remaining))s remaining")
            
            // Check buffer status near loop point
            let ranges = currentItem.loadedTimeRanges
            if let lastRange = ranges.last {
                let timeRange = lastRange.timeRangeValue
                let endTime = CMTimeAdd(timeRange.start, timeRange.duration)
                let bufferedSeconds = CMTimeGetSeconds(endTime)
                logger.debug("🔄 [LOOP-DEBUG] Buffer extends to: \(String(format: "%.3f", bufferedSeconds))s")
            }
        }
        
        // Log queue status periodically (every 5 seconds)
        if Int(currentTimeSeconds) % 5 == 0 && currentTimeSeconds.truncatingRemainder(dividingBy: 1.0) < 0.1 {
            logger.debug("🔄 [LOOP-DEBUG] Queue has \(player.items().count) items, playing: \(mediaItem.fileName)")
        }
    }
    
    /// Cleanup debug observers
    internal func cleanupLooperDebugging(for player: AVPlayer) {
        // Remove time observer
        if let timeObserver = objc_getAssociatedObject(player, "debugTimeObserver") {
            player.removeTimeObserver(timeObserver)
            objc_setAssociatedObject(player, "debugTimeObserver", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        // Check if this player had observers added (marked with a flag)
        let hasObserversFlag = objc_getAssociatedObject(player, "hasKVOObservers") as? Bool ?? false
        if hasObserversFlag {
            player.removeObserver(self, forKeyPath: "currentItem")
            objc_setAssociatedObject(player, "hasKVOObservers", false, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        // Check if current item had observers
        if let currentItem = player.currentItem {
            let hasItemObserversFlag = objc_getAssociatedObject(currentItem, "hasKVOObservers") as? Bool ?? false
            if hasItemObserversFlag {
                currentItem.removeObserver(self, forKeyPath: "status")
                currentItem.removeObserver(self, forKeyPath: "loadedTimeRanges")
                currentItem.removeObserver(self, forKeyPath: "playbackBufferEmpty")
                currentItem.removeObserver(self, forKeyPath: "playbackLikelyToKeepUp")
                objc_setAssociatedObject(currentItem, "hasKVOObservers", false, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
        
        // Check if looper had observers
        if let looper = playerLooper {
            let hasLooperObserversFlag = objc_getAssociatedObject(looper, "hasKVOObservers") as? Bool ?? false
            if hasLooperObserversFlag {
                looper.removeObserver(self, forKeyPath: "status")
                objc_setAssociatedObject(looper, "hasKVOObservers", false, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
        }
        
        logger.debug("🔍 [DEBUG] Looper debugging cleaned up")
    }
    
    /// Log detailed player configuration for debugging
    private func logPlayerConfiguration(player: AVQueuePlayer, mediaItem: MediaItem) {
        logger.debug("🔧 [CONFIG] Player Configuration for: \(mediaItem.fileName)")
        logger.debug("🔧 [CONFIG] - Queue items: \(player.items().count)")
        logger.debug("🔧 [CONFIG] - Automatically waits to minimize stalling: \(player.automaticallyWaitsToMinimizeStalling)")
        logger.debug("🔧 [CONFIG] - Prevents display sleep: \(player.preventsDisplaySleepDuringVideoPlayback)")
        logger.debug("🔧 [CONFIG] - Is muted: \(player.isMuted)")
        logger.debug("🔧 [CONFIG] - Playback rate: \(player.rate)")
        
        if let currentItem = player.currentItem {
            logger.debug("🔧 [CONFIG] - Preferred forward buffer duration: \(currentItem.preferredForwardBufferDuration)")
            logger.debug("🔧 [CONFIG] - Preferred peak bit rate: \(currentItem.preferredPeakBitRate)")
            logger.debug("🔧 [CONFIG] - Can use network resources while paused: \(currentItem.canUseNetworkResourcesForLiveStreamingWhilePaused)")
            
            if let asset = currentItem.asset as? AVURLAsset {
                logger.debug("🔧 [CONFIG] - Asset URL: \(asset.url.lastPathComponent)")
            }
        }
        
        if let looper = playerLooper {
            logger.debug("🔧 [CONFIG] - AVPlayerLooper status: \(looper.status.rawValue)")
            logger.debug("🔧 [CONFIG] - AVPlayerLooper loop count: \(looper.loopCount)")
        }
    }
    #endif
    
    /// Sets up a player with seamless looping if enabled
    private func setupPlayer(for mediaItem: MediaItem) -> AVPlayer {
        let url = URL(fileURLWithPath: mediaItem.path)
        let settings = viewModel.getVideoSettings(for: mediaItem)
        
        // Try to get cached asset first for faster loading
        let cachedAsset = VideoCacheManager.shared.getCachedAsset(for: mediaItem.path)
        
        if settings.isLooping {
            // Create multiple player items for truly gapless looping
            let playerItem1: AVPlayerItem
            let playerItem2: AVPlayerItem
            
            if let asset = cachedAsset {
                // Use cached asset for faster loading
                playerItem1 = AVPlayerItem(asset: asset)
                playerItem2 = AVPlayerItem(asset: asset)
                logger.debug("🚀 Using cached asset for looping player: \(mediaItem.fileName)")
            } else {
                // Fallback to URL-based loading
                playerItem1 = AVPlayerItem(url: url)
                playerItem2 = AVPlayerItem(url: url)
                logger.debug("📁 Using file URL for looping player: \(mediaItem.fileName)")
            }
            
            // Configure both items for optimal buffering
            [playerItem1, playerItem2].forEach { item in
                item.preferredForwardBufferDuration = 10.0  // Increased buffer
                item.canUseNetworkResourcesForLiveStreamingWhilePaused = false
                // Preload to minimize stutter
                item.preferredPeakBitRate = 0  // No bit rate limit for local files
            }
            
            // Create queue player with multiple items for seamless transition
            let queuePlayer = AVQueuePlayer(items: [playerItem1, playerItem2])
            
            // Configure queue player for optimal looping
            queuePlayer.automaticallyWaitsToMinimizeStalling = false
            queuePlayer.preventsDisplaySleepDuringVideoPlayback = true
            
            // Create AVPlayerLooper - this will automatically manage the queue
            playerLooper = AVPlayerLooper(player: queuePlayer, templateItem: playerItem1)
            
            // Apply settings
            queuePlayer.isMuted = settings.isMuted
            queuePlayer.rate = settings.playbackRate
            
            logger.debug("🔄 Created dual-item seamless looping player for: \(mediaItem.fileName)")
            
            // Add debug monitoring for the looper
            #if DEBUG
            addLooperDebugging(for: queuePlayer, mediaItem: mediaItem)
            logPlayerConfiguration(player: queuePlayer, mediaItem: mediaItem)
            #endif
            
            return queuePlayer
        } else {
            // Create regular AVPlayer for non-looping videos
            let player: AVPlayer
            
            if let asset = cachedAsset {
                // Use cached asset for faster loading
                let playerItem = AVPlayerItem(asset: asset)
                player = AVPlayer(playerItem: playerItem)
                logger.debug("🚀 Using cached asset for regular player: \(mediaItem.fileName)")
            } else {
                // Fallback to URL-based loading
                player = AVPlayer(url: url)
                logger.debug("📁 Using file URL for regular player: \(mediaItem.fileName)")
            }
            
            // Apply settings
            player.isMuted = settings.isMuted
            player.rate = settings.playbackRate
            
            // Clear any existing looper
            playerLooper = nil
            
            logger.debug("▶️ Created regular player for: \(mediaItem.fileName)")
            return player
        }
    }
    
    /// Displays the media at the current index with a smooth dissolve transition
    private func displayImageAtCurrentIndexWithDissolveTransition() {
        guard let currentPath = dataSource.getCurrentPath() else {
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
    
    /// Displays a video with a smooth dissolve transition from current content
    private func displayVideoWithDissolveTransition(_ mediaItem: MediaItem) {
        logger.info("🎬 [DISSOLVE] Transitioning to video: \(mediaItem.fileName)")
        
        Task { @MainActor in
            // Create player with seamless looping support
            let player = self.setupPlayer(for: mediaItem)
            
            await MainActor.run {
                // Create a temporary overlay to prevent black flash
                let tempOverlay = UIView(frame: self.view.bounds)
                tempOverlay.backgroundColor = .black
                
                // Capture current frame if there's a video playing
                if self.isVideo, let currentPlayer = self.playerView.player {
                    // Try to capture the current video frame as a snapshot
                    if let snapshot = self.playerView.view.snapshotView(afterScreenUpdates: false) {
                        snapshot.frame = self.view.bounds
                        tempOverlay.addSubview(snapshot)
                    }
                } else if !self.imageView.isHidden, let currentImage = self.imageView.image {
                    // If transitioning from an image, use that as overlay
                    let imageView = UIImageView(image: currentImage)
                    imageView.contentMode = .scaleAspectFill
                    imageView.clipsToBounds = true
                    imageView.frame = self.view.bounds
                    tempOverlay.addSubview(imageView)
                }
                
                self.view.addSubview(tempOverlay)
                
                // Stop and clean up old video
                if self.isVideo {
                    self.playerView.player?.pause()
                    self.playerControlsAutoHideTimer?.invalidate()
                    self.playerControlsAutoHideTimer = nil
                    self.cleanupPlayerLooper()
                }
                
                // Set up the main player view with the new player
                self.setupPlayerView()
                self.playerView.player = player
                self.playerView.showsPlaybackControls = false
                self.playerView.view.isHidden = false
                self.playerView.view.alpha = 1  // Keep visible
                self.isVideo = true
                
                // Add observer for playback end
                self.addManagedObserver(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem) { [weak self] _ in
                    self?.handleVideoPlaybackEnd(for: mediaItem)
                }
                
                // Start playback and wait for first frame
                player.play()
                
                // Wait for the video to be ready to display - use a reasonable delay
                // that allows the first frame to render without being too long
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                    // Create smooth dissolve transition
                    UIView.animate(withDuration: 0.4, animations: {
                        tempOverlay.alpha = 0
                    }) { _ in
                        // Clean up
                        tempOverlay.removeFromSuperview()
                        self.imageView.isHidden = true
                        self.imageView.alpha = 1  // Reset for future use
                        
                        self.setNeedsFocusUpdate()
                        self.updateFocusIfNeeded()
                    }
                }
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
                    self.playerControlsAutoHideTimer?.invalidate()
                    self.playerControlsAutoHideTimer = nil
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
    
    /// Debug helper to log imageView state
    private func debugImageViewState(_ label: String) {
        logger.debug("🔍 [DEBUG-\(label)] ImageView state:")
        logger.debug("🔍 [DEBUG-\(label)]   - isHidden: \(self.imageView.isHidden)")
        logger.debug("🔍 [DEBUG-\(label)]   - alpha: \(self.imageView.alpha)")
        logger.debug("🔍 [DEBUG-\(label)]   - frame: \(String(describing: self.imageView.frame))")
        logger.debug("🔍 [DEBUG-\(label)]   - bounds: \(String(describing: self.imageView.bounds))")
        logger.debug("🔍 [DEBUG-\(label)]   - superview: \(self.imageView.superview != nil ? "present" : "nil")")
        logger.debug("🔍 [DEBUG-\(label)]   - image: \(self.imageView.image != nil ? "present" : "nil")")
        if let image = self.imageView.image {
            logger.debug("🔍 [DEBUG-\(label)]   - image size: \(String(describing: image.size))")
        }
        logger.debug("🔍 [DEBUG-\(label)]   - contentMode: \(self.imageView.contentMode.rawValue)")
        logger.debug("🔍 [DEBUG-\(label)]   - clipsToBounds: \(self.imageView.clipsToBounds)")
        logger.debug("🔍 [DEBUG-\(label)]   - backgroundColor: \(self.imageView.backgroundColor?.description ?? "nil")")
        logger.debug("🔍 [DEBUG-\(label)]   - transform: \(String(describing: self.imageView.transform))")
        
        // Check view hierarchy
        if let superview = self.imageView.superview {
            logger.debug("🔍 [DEBUG-\(label)] View hierarchy:")
            var currentView = self.imageView as UIView
            var level = 0
            while let parent = currentView.superview {
                let indent = String(repeating: "  ", count: level)
                logger.debug("🔍 [DEBUG-\(label)]   \(indent)↳ \(type(of: parent)) - frame: \(String(describing: parent.frame)), isHidden: \(parent.isHidden), alpha: \(parent.alpha)")
                currentView = parent
                level += 1
                if level > 5 { break } // Prevent infinite loops
            }
        }
        
        // Check if there are views in front of imageView
        if let superview = self.imageView.superview {
            let imageViewIndex = superview.subviews.firstIndex(of: self.imageView) ?? -1
            logger.debug("🔍 [DEBUG-\(label)] ImageView z-index: \(imageViewIndex) out of \(superview.subviews.count) subviews")
            
            // List views that are above imageView
            for (index, subview) in superview.subviews.enumerated() {
                if index > imageViewIndex {
                    logger.debug("🔍 [DEBUG-\(label)]   View above imageView: \(type(of: subview)) - isHidden: \(subview.isHidden), alpha: \(subview.alpha)")
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
    
    /// Moves to the next image in the collection
    internal func nextImage() {
        guard !isInGridMode else { return }
        
        let oldIndex = dataSource.currentIndex
        if dataSource.nextIndex() {
            let newIndex = dataSource.currentIndex
            logger.debug("📍 [NAVIGATION] nextImage() - moved from index \(oldIndex) to \(newIndex)")
            
            // Preload videos around the new index for smooth future transitions
            VideoCacheManager.shared.preloadVideosAroundIndex(newIndex, in: dataSource)
            
            displayImageAtCurrentIndexWithDissolveTransition()
        } else {
            logger.debug("📍 [NAVIGATION] nextImage() - already at last image (index \(oldIndex))")
        }
    }
    
    /// Moves to the previous image in the collection
    internal func previousImage() {
        guard !isInGridMode else { return }
        
        let oldIndex = dataSource.currentIndex
        if dataSource.previousIndex() {
            let newIndex = dataSource.currentIndex
            logger.debug("📍 [NAVIGATION] previousImage() - moved from index \(oldIndex) to \(newIndex)")
            
            // Preload videos around the new index for smooth future transitions
            VideoCacheManager.shared.preloadVideosAroundIndex(newIndex, in: dataSource)
            
            displayImageAtCurrentIndexWithDissolveTransition()
        } else {
            logger.debug("📍 [NAVIGATION] previousImage() - already at first image (index \(oldIndex))")
        }
    }
    
    /// Loads the sample images bundled with the app
    internal func loadSampleImages() {
        logger.info("Loading sample images")
        activityIndicator.startAnimating()
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            var addedImages = false
            
            for imageName in self.sampleImageNames {
                if let image = UIImage(named: imageName),
                   let imageData = image.jpegData(compressionQuality: 1.0) {
                    
                    // Save sample image using ImageStorage
                    if let fileURL = self.imageStorage.saveSampleImage(imageData, name: imageName) {
                        DispatchQueue.main.async { [weak self] in
                            self?.dataSource.addMedia(at: fileURL.path)
                            addedImages = true
                        }
                    }
                } else {
                    self.logger.error("Failed to load sample image named: \(imageName)")
                }
            }
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                self.activityIndicator.stopAnimating()
                
                // If we added images successfully, show the grid and select the first one
                if !self.dataSource.isEmpty {
                    self.gridView.reloadData()
                    
                    // Select the first image by default
                    let indexPath = IndexPath(item: 0, section: 0)
                    self.gridView.selectItem(at: indexPath, animated: false, scrollPosition: .top)
                    
                    if let cell = self.gridView.cellForItem(at: indexPath) {
                        cell.setNeedsFocusUpdate()
                    }
                    
                    // Hide empty state if it was showing
                    self.hideEmptyState()
                    
                    // Show grid view
                    self.showGridView()
                } else {
                    // Show an error if no sample images could be loaded
                    ErrorHandler.shared.handle(.emptyLibrary, context: "loadSampleImages")
                }
            }
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
            
            // Clean up player controls timer
            playerControlsAutoHideTimer?.invalidate()
            playerControlsAutoHideTimer = nil
            cleanupPlayerLooper()
        }
        
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
        let wasInGridMode = isInGridMode
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
    
    func createImageAtIndex(_ index: Int) -> UIImage? {
        guard let path = dataSource.getPath(at: index) else { return nil }
        
        let url = URL(fileURLWithPath: path)
        
        // Check if it's a video file
        if url.pathExtension.lowercased() == "mp4" || url.pathExtension.lowercased() == "mov" {
            // Check cache first
            if let cachedThumbnail = VideoThumbnailCache.shared.getThumbnail(for: url.path) {
                return cachedThumbnail
            }
            
            // Generate thumbnail for video
            let asset = AVURLAsset(url: url)
            let imageGenerator = AVAssetImageGenerator(asset: asset)
            imageGenerator.appliesPreferredTrackTransform = true
            imageGenerator.maximumSize = CGSize(width: 1920, height: 1080) // Higher resolution for fullscreen display
            
            // Set requestedTimeToleranceBefore and After to get better performance
            imageGenerator.requestedTimeToleranceBefore = CMTime.positiveInfinity
            imageGenerator.requestedTimeToleranceAfter = CMTime.positiveInfinity
            
            // Try multiple timestamps for better thumbnail selection
            let timePoints: [CMTime] = [
                CMTime(seconds: 2.0, preferredTimescale: 600),   // Try 2 seconds in
                CMTime(seconds: 5.0, preferredTimescale: 600),   // Try 5 seconds in
                CMTime(seconds: 10.0, preferredTimescale: 600),  // Try 10 seconds in
                CMTime(seconds: 15.0, preferredTimescale: 600),  // Try 15 seconds in
                CMTime(seconds: 0.5, preferredTimescale: 600),   // Try 0.5 seconds in
                CMTime.zero                                      // Fallback to first frame
            ]
            
            var bestThumbnail: UIImage? = nil
            var highestScore = 0.0
            
            // Try each time point until we get a valid image
            for timePoint in timePoints {
                do {
                    let cgImage = try imageGenerator.copyCGImage(at: timePoint, actualTime: nil)
                    let thumbnail = UIImage(cgImage: cgImage)
                    
                    // Simple thumbnail quality score (could be enhanced further)
                    if let score = calculateImageQualityScore(thumbnail) {
                        if score > highestScore {
                            highestScore = score
                            bestThumbnail = thumbnail
                        }
                    }
                    
                    // If this is our first valid thumbnail, remember it
                    if bestThumbnail == nil {
                        bestThumbnail = thumbnail
                    }
                } catch {
                    logger.warning("Failed to generate thumbnail at time \(timePoint.seconds): \(error.localizedDescription)")
                    // Continue to next time point
                }
            }
            
            // If we got a valid thumbnail
            if let bestThumbnail = bestThumbnail {
                // Cache the thumbnail for future use
                VideoThumbnailCache.shared.cacheThumbnail(bestThumbnail, for: url.path)
                return bestThumbnail
            }
            
            // If all time points failed, return a placeholder
            ErrorHandler.shared.handle(.thumbnailGenerationFailed(path: url.path, timeStamp: nil), context: "createImageAtIndex")
            if let placeholder = UIImage(systemName: "video.fill")?.withTintColor(.white, renderingMode: .alwaysOriginal) {
                return placeholder
            }
            return nil
        }
        
        // Handle image files
        if let image = UIImage(contentsOfFile: path) {
            return image
        }
        
        ErrorHandler.shared.handle(.fileCorrupted(path: path, reason: "Could not decode image file"), context: "createImageAtIndex")
        return nil
    }
    
    // Helper to evaluate thumbnail quality
    private func calculateImageQualityScore(_ image: UIImage?) -> Double? {
        guard let image = image, let cgImage = image.cgImage else { return nil }
        
        // Get image dimensions
        let width = cgImage.width
        let height = cgImage.height
        
        // Simple image variance calculation as quality metric
        // Higher variance typically means more detail/information
        if width < 10 || height < 10 {
            return 0.0  // Too small to be useful
        }
        
        // For performance, we'll sample the image instead of analyzing every pixel
        let context = CIContext()
        let ciImage = CIImage(cgImage: cgImage)
        
        // Calculate brightness variance
        if let extent = ciImage.extent.standardized as CGRect? {
            if extent.width > 1 && extent.height > 1 {
                // Very simple entropy-based measure that works well enough for thumbnails
                let averageBrightness = ciImage.averageBrightness(in: context)
                
                // Penalize extremely dark images that are likely black frames
                if averageBrightness < 0.1 {
                    return 0.1
                }
                
                // Penalize extremely bright images that are likely flash frames
                if averageBrightness > 0.9 {
                    return 0.2
                }
                
                // Calculate a rough metric for detail (could be made more sophisticated)
                let detailScore = ciImage.calculateDetailScore(in: context)
                
                return 0.3 + (detailScore * 0.7) // Weight detail more heavily
            }
        }
        
        return 0.5 // Default middle score
    }
    
    // MARK: - Image Positioning
    
    /// Applies stored position for the given image path
    private func applyStoredImagePosition(for imagePath: String) {
        if let storedPosition = imagePositions[imagePath] {
            imageView.transform = CGAffineTransform(translationX: storedPosition.x, y: storedPosition.y)
        } else {
            // Reset to no transform for new images
            imageView.transform = .identity
        }
    }
}
