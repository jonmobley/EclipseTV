// ImageViewController+VideoPlayback.swift
import UIKit
import AVFoundation
import AVKit
import ObjectiveC

// MARK: - Video Playback

extension ImageViewController {

    /// Installs the end-of-playback observer for the given player, first removing any
    /// previously installed end observers so they do not stack across video navigation.
    private func installVideoEndObserver(for player: AVPlayer, mediaItem: MediaItem) {
        resourceManager.removeNotificationObservers(for: .AVPlayerItemDidPlayToEndTime)
        addManagedObserver(for: .AVPlayerItemDidPlayToEndTime, object: player.currentItem) { [weak self] _ in
            self?.handleVideoPlaybackEnd(for: mediaItem)
        }
    }

    /// Calls `play()` once the item is ready, prerolling to ensure a first frame is
    /// decoded before we reveal the player (avoids AVPlayerViewController's spinner).
    private func startWhenReady(_ player: AVPlayer, reveal: @escaping () -> Void) {
        guard let item = player.currentItem else {
            player.play()
            reveal()
            return
        }

        if item.status == .readyToPlay {
            player.preroll(atRate: 1.0) { _ in
                player.play()
                reveal()
            }
            return
        }

        // Observe readiness with a timeout fallback so we never hang.
        var token: NSKeyValueObservation?
        token = item.observe(\.status, options: [.new]) { observingItem, _ in
            if observingItem.status == .readyToPlay {
                token?.invalidate()
                token = nil
                player.preroll(atRate: 1.0) { _ in
                    player.play()
                    reveal()
                }
            }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            guard token != nil else { return }
            token?.invalidate()
            token = nil
            player.play()
            reveal()
        }
    }

    internal func displayVideo(_ mediaItem: MediaItem) {
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

                // Add observer for playback end (removes any prior observers first)
                self.installVideoEndObserver(for: player, mediaItem: mediaItem)

                // Start playback once the first frame is ready to avoid the spinner
                self.startWhenReady(player) {
                    self.activityIndicator.stopAnimating()
                }
            }
        }
    }

    internal func displayVideoWithTransition(_ mediaItem: MediaItem) {
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

                // Add observer for playback end (removes any prior observers first)
                self.installVideoEndObserver(for: player, mediaItem: mediaItem)

                // Fade in the player only once the first frame is ready to avoid the spinner
                self.startWhenReady(player) {
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
    #endif

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

    #if DEBUG
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
            queuePlayer.volume = settings.volume
            // Note: Don't set rate directly here - let play() method handle playback start
            // Setting rate directly can interfere with pause/play logic

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

            // Start rendering as soon as the first frame is available instead of
            // pre-buffering, which is the right trade-off for local files.
            player.automaticallyWaitsToMinimizeStalling = false

            // Apply settings
            player.isMuted = settings.isMuted
            player.volume = settings.volume
            // Note: Don't set rate directly here - let play() method handle playback start
            // Setting rate directly can interfere with pause/play logic

            // Clear any existing looper
            playerLooper = nil

            logger.debug("▶️ Created regular player for: \(mediaItem.fileName)")
            return player
        }
    }

    /// Rebuilds the active player to apply a setting that can't be changed on a live
    /// player (e.g. toggling loop swaps between `AVPlayer` and `AVQueuePlayer`+looper).
    /// Preserves the current playback position and play/pause state.
    internal func rebuildCurrentVideoPlayer(for mediaItem: MediaItem) {
        let wasPlaying = (playerView.player?.rate ?? 0) > 0
        let resumeTime = playerView.player?.currentTime() ?? .zero

        // Tear down the existing player/looper before swapping in a new one.
        playerView.player?.pause()
        cleanupPlayerLooper()

        let player = setupPlayer(for: mediaItem)
        playerView.player = player
        installVideoEndObserver(for: player, mediaItem: mediaItem)

        player.seek(to: resumeTime, toleranceBefore: .zero, toleranceAfter: .zero) { _ in
            if wasPlaying {
                player.play()
            }
        }

        logger.debug("🔁 Rebuilt active player to apply loop change for: \(mediaItem.fileName)")
    }

    /// Displays a video with a smooth dissolve transition from current content
    internal func displayVideoWithDissolveTransition(_ mediaItem: MediaItem) {
        logger.info("🎬 [DISSOLVE] Transitioning to video: \(mediaItem.fileName)")

        Task { @MainActor in
            // Create player with seamless looping support
            let player = self.setupPlayer(for: mediaItem)

            await MainActor.run {
                // Create a temporary overlay to prevent black flash
                let tempOverlay = UIView(frame: self.view.bounds)
                tempOverlay.backgroundColor = .black

                // Capture current frame if there's a video playing
                if self.isVideo, self.playerView.player != nil {
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
                    self.cleanupPlayerLooper()
                }

                // Set up the main player view with the new player
                self.setupPlayerView()
                self.playerView.player = player
                self.playerView.view.isHidden = false
                self.playerView.view.alpha = 1  // Keep visible
                self.isVideo = true

                // Add observer for playback end (removes any prior observers first)
                self.installVideoEndObserver(for: player, mediaItem: mediaItem)

                // Dissolve the overlay only once the first frame is ready, which both
                // hides the spinner and avoids a black flash during the transition.
                self.startWhenReady(player) {
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
}
