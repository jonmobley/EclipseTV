// ImageViewController+VideoSettings.swift
import UIKit
import os.log
import AVKit

// MARK: - Video Settings

extension ImageViewController {
    /// Clean up player looper resources
    func cleanupPlayerLooper() {
        #if DEBUG
        if let player = playerView.player {
            cleanupLooperDebugging(for: player)
        }
        #endif
        playerLooper = nil
    }

    /// Apply settings to currently playing video (if any)
    func applySettingsToCurrentVideo() {
        guard isVideo, let player = playerView.player else { return }
        guard let currentPath = dataSource.getCurrentPath() else { return }

        // Get settings from the new system (viewModel)
        let mediaItem = MediaItem(path: currentPath)
        let settings = viewModel.getVideoSettings(for: mediaItem)

        // Apply mute setting immediately
        player.isMuted = settings.isMuted

        // Note: Loop setting will be applied when video ends
        logger.info("Applied settings to current video: muted=\(settings.isMuted), loop=\(settings.isLooping)")
    }

    #if DEBUG
    /// Handle KVO observations for debug monitoring
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        guard let keyPath = keyPath else { return }

        switch keyPath {
        case "status":
            if let looper = object as? AVPlayerLooper {
                let status = looper.status
                logger.debug("🔍 [DEBUG] AVPlayerLooper status changed to: \(status.rawValue)")
                if status == .failed, let error = looper.error {
                    logger.error("🔍 [DEBUG] AVPlayerLooper failed with error: \(error)")
                }
            } else if let item = object as? AVPlayerItem {
                let status = item.status
                logger.debug("🔍 [DEBUG] AVPlayerItem status changed to: \(status.rawValue)")
                if status == .failed, let error = item.error {
                    logger.error("🔍 [DEBUG] AVPlayerItem failed with error: \(error)")
                }
            }

        case "loadedTimeRanges":
            if let item = object as? AVPlayerItem {
                let ranges = item.loadedTimeRanges
                if let lastRange = ranges.last {
                    let timeRange = lastRange.timeRangeValue
                    let duration = CMTimeGetSeconds(timeRange.duration)
                    logger.debug("🔍 [DEBUG] Buffer loaded: \(String(format: "%.2f", duration))s")
                }
            }

        case "playbackBufferEmpty":
            if let item = object as? AVPlayerItem {
                logger.debug("🔍 [DEBUG] Playback buffer empty: \(item.isPlaybackBufferEmpty)")
            }

        case "playbackLikelyToKeepUp":
            if let item = object as? AVPlayerItem {
                logger.debug("🔍 [DEBUG] Playback likely to keep up: \(item.isPlaybackLikelyToKeepUp)")
            }

        case "currentItem":
            if object is AVQueuePlayer {
                if change?[.newKey] is AVPlayerItem {
                    logger.debug("🔍 [DEBUG] Queue player current item changed to new item")
                } else {
                    logger.debug("🔍 [DEBUG] Queue player current item changed to nil")
                }
            }

        default:
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }
    #endif
}
