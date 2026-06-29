// iPhoneConnectionManager+Transfers.swift
import UIKit
import MultipeerConnectivity

// MARK: - Media Transfers

/// User-initiated media sends to the active TV, with progress reporting (observed in the
/// core file's `observeValue`). Also keeps a local full-res copy for AirPlay presentation
/// and fans the file out to any sync replicas.
extension iPhoneConnectionManager {

    func sendImage(at imageURL: URL) -> Bool {
        guard let session = session, let peer = activeTargetPeer else {
            logger.error("Cannot send image: No active session or peer")
            return false
        }

        isTransferCancelled = false
        isTransferringVideo = false

        // Clean up any existing progress observer before starting new transfer
        cleanupCurrentProgress()

        sendPendingRestoreIfNeeded(to: peer, via: session)

        let fileName = imageURL.lastPathComponent
        // Keep a full-resolution copy on the phone so it can be presented on an external
        // AirPlay display without the TV-side companion app. Keyed by the resource name,
        // which becomes this item's id in the TV library.
        LocalMediaStore.shared.store(fileURL: imageURL, forId: fileName)
        // Replicate to other synced TVs (no progress UI for those).
        fanOutMediaToReplicas(url: imageURL, id: fileName, excluding: peer)
        let progress = session.sendResource(at: imageURL, withName: fileName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Always clean up observer when transfer completes
                self.cleanupCurrentProgress()
                
                if let error = error {
                    self.logger.error("Image transfer failed: \(error.localizedDescription)")
                    self.delegate?.connectionManager(self, didFailTransferIsVideo: false, error: error)
                } else {
                    self.logger.info("Image transfer completed successfully.")
                    self.delegate?.connectionManager(self, didUpdateImageTransferProgress: 100)
                }
                
                self.currentTransferTask = nil
            }
        }
        
        // Store progress and register for observation
        if let progress = progress {
            currentProgress = progress
            currentTransferTask = progress
            progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: .new, context: nil)
        }
        
        return true
    }

    /// Reports send progress to the delegate. Overrides the `@objc` NSObject KVO hook;
    /// kept with the transfer setup that registers the observer.
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == #keyPath(Progress.fractionCompleted),
           let progress = object as? Progress {
            let percent = progress.fractionCompleted * 100
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                
                // Check if this is a video transfer or an image transfer
                if self.isTransferringVideo {
                    self.delegate?.connectionManager(self, didUpdateVideoTransferProgress: percent)
                } else {
                    self.delegate?.connectionManager(self, didUpdateImageTransferProgress: percent)
                }
            }
        }
    }

    func cancelCurrentTransfer() {
        isTransferCancelled = true
        currentTransferTask?.cancel()
        currentTransferTask = nil
        
        // Use the centralized cleanup method
        cleanupCurrentProgress()
        
        isTransferringVideo = false
    }

    func sendVideoData(_ videoURL: URL) -> Bool {
        guard let session = session, let peer = activeTargetPeer else {
            logger.error("Cannot send video: No active session or peer")
            return false
        }

        isTransferCancelled = false
        isTransferringVideo = true

        // Clean up any existing progress observer before starting new transfer
        cleanupCurrentProgress()

        // Check if there's a custom thumbnail to send first
        let fileName = videoURL.lastPathComponent
        if let customThumbnailPath = UserDefaults.standard.string(forKey: "customThumbnail_\(fileName)"),
           FileManager.default.fileExists(atPath: customThumbnailPath) {
            
            // Send custom thumbnail first, then send the video only once the thumbnail
            // transfer completes so the Apple TV always has the thumbnail before the video.
            let thumbnailURL = URL(fileURLWithPath: customThumbnailPath)
            let thumbnailFileName = "thumbnail_\(fileName)"
            
            session.sendResource(at: thumbnailURL, withName: thumbnailFileName, toPeer: peer) { [weak self] error in
                if let error = error {
                    self?.logger.error("Custom thumbnail transfer failed: \(error.localizedDescription)")
                } else {
                    self?.logger.info("Custom thumbnail sent successfully")
                }
                // Clean up the temporary thumbnail file
                try? FileManager.default.removeItem(at: thumbnailURL)
                UserDefaults.standard.removeObject(forKey: "customThumbnail_\(fileName)")
                
                // Now send the video itself
                DispatchQueue.main.async {
                    self?.beginVideoResourceSend(videoURL, session: session, peer: peer)
                }
            }
        } else {
            // No custom thumbnail; send the video immediately
            beginVideoResourceSend(videoURL, session: session, peer: peer)
        }
        
        return true
    }

    /// Performs the actual video resource transfer and wires up progress observation.
    private func beginVideoResourceSend(_ videoURL: URL, session: MCSession, peer: MCPeerID) {
        guard !isTransferCancelled else {
            logger.info("Video transfer cancelled before it began")
            return
        }

        sendPendingRestoreIfNeeded(to: peer, via: session)

        let fileName = videoURL.lastPathComponent
        // Keep a full-resolution copy on the phone for external AirPlay presentation
        // (see sendImage for rationale).
        LocalMediaStore.shared.store(fileURL: videoURL, forId: fileName)
        // Replicate to other synced TVs (no progress UI for those).
        fanOutMediaToReplicas(url: videoURL, id: fileName, excluding: peer)
        let progress = session.sendResource(at: videoURL, withName: fileName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Always clean up observer when transfer completes
                self.cleanupCurrentProgress()
                self.isTransferringVideo = false
                
                if let error = error {
                    self.logger.error("Video transfer failed: \(error.localizedDescription)")
                    self.delegate?.connectionManager(self, didFailTransferIsVideo: true, error: error)
                } else {
                    self.logger.info("Video transfer completed successfully.")
                    self.delegate?.connectionManager(self, didUpdateVideoTransferProgress: 100)
                }
                
                self.currentTransferTask = nil
            }
        }
        
        // Store progress and register for observation
        if let progress = progress {
            currentProgress = progress
            currentTransferTask = progress
            progress.addObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted), options: .new, context: nil)
        }
    }

    /// Fans a just-sent media file out to every connected replica TV (all connected peers
    /// except the active one). No-op unless syncing all.
    private func fanOutMediaToReplicas(url: URL, id: String, excluding active: MCPeerID) {
        guard syncAllEnabled, let session = session else { return }
        for peer in session.connectedPeers where peer != active {
            sendMedia(at: url, id: id, to: peer)
        }
    }

    /// If a re-send was requested, tells the TV the upcoming resource restores a purged
    /// item, then clears the flag so subsequent normal sends aren't treated as restores.
    private func sendPendingRestoreIfNeeded(to peer: MCPeerID, via session: MCSession) {
        guard let restoreId = pendingRestoreId else { return }
        pendingRestoreId = nil
        if let data = EclipseShareEnvelope.restoreItem(id: restoreId).encoded() {
            try? session.send(data, toPeers: [peer], with: .reliable)
            logger.info("Sent restore_item for id: \(restoreId)")
        }
    }
}
