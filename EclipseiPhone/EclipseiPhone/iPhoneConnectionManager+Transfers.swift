// iPhoneConnectionManager+Transfers.swift
import UIKit
import MultipeerConnectivity

// MARK: - Media Transfers

/// User-initiated media sends to the active TV, with progress reporting (observed in the
/// core file's `observeValue`). Also keeps a local full-res copy for AirPlay presentation
/// and fans the file out to any sync replicas.
extension iPhoneConnectionManager {

    /// Sends only a custom poster (`thumbnail_<file>`) for a video already on the TV.
    @discardableResult
    func sendCustomVideoThumbnail(_ image: UIImage, videoFileName: String) -> Bool {
        guard let session = session, let peer = activeTargetPeer else { return false }
        guard let data = image.jpegData(compressionQuality: 0.8) else { return false }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumbnail_\(videoFileName).jpg")
        do {
            try data.write(to: tempURL, options: .atomic)
        } catch {
            return false
        }

        let mode = ExternalOutputSettings.libraryMode
        let wireName = EclipseShareProtocol.mediaResourceName(
            for: "thumbnail_\(videoFileName)", mode: mode
        )
        session.sendResource(at: tempURL, withName: wireName, toPeer: peer) { [weak self] error in
            try? FileManager.default.removeItem(at: tempURL)
            if let error {
                self?.logger.error(
                    "Custom thumbnail update failed: \(error.localizedDescription)"
                )
            }
        }
        return true
    }

    func sendImage(at imageURL: URL) -> Bool {
        guard let session = session, let peer = activeTargetPeer else {
            logger.error("Cannot send image: No active session or peer")
            return false
        }

        transferGeneration &+= 1
        let generation = transferGeneration
        isTransferCancelled = false
        isTransferringVideo = false

        // Clean up any existing progress observer before starting new transfer
        cleanupCurrentProgress()

        let restoreId = sendPendingRestoreIfNeeded(to: peer, via: session)

        let fileName = imageURL.lastPathComponent
        let mode = ExternalOutputSettings.libraryMode
        // Keep a full-resolution copy on the phone so it can be presented on an external
        // AirPlay display without the TV-side companion app. Keyed by the library id
        // (plain file name), not the mode-stamped Multipeer wire name.
        LocalMediaStore.shared.store(fileURL: imageURL, forId: fileName, mode: mode)
        // Replicate to other synced TVs (no progress UI for those).
        fanOutMediaToReplicas(
            url: imageURL,
            id: fileName,
            mode: mode,
            excluding: peer,
            restoreId: restoreId
        )
        let wireName = EclipseShareProtocol.mediaResourceName(for: fileName, mode: mode)
        let progress = session.sendResource(at: imageURL, withName: wireName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, self.transferGeneration == generation else { return }
                
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
        transferGeneration &+= 1
        isTransferCancelled = true
        currentTransferTask?.cancel()
        currentTransferTask = nil

        // Cancelling only the active TV's send left the same file still uploading to every
        // sync replica, so a cancelled item appeared on the replicas but not the active TV.
        cancelReplicaFanOut()

        // Use the centralized cleanup method
        cleanupCurrentProgress()
        
        isTransferringVideo = false
    }

    /// Cancels in-flight replica sends and forgets their progress objects.
    private func cancelReplicaFanOut() {
        for progress in replicaTransferProgress {
            progress.cancel()
        }
        replicaTransferProgress.removeAll()
    }

    func sendVideoData(_ videoURL: URL) -> Bool {
        guard let session = session, let peer = activeTargetPeer else {
            logger.error("Cannot send video: No active session or peer")
            return false
        }

        transferGeneration &+= 1
        let generation = transferGeneration
        isTransferCancelled = false
        isTransferringVideo = true

        // Clean up any existing progress observer before starting new transfer
        cleanupCurrentProgress()

        // Capture mode once so a mid-transfer display-mode switch can't mis-bucket.
        let mode = ExternalOutputSettings.libraryMode

        // Check if there's a custom thumbnail to send first
        let fileName = videoURL.lastPathComponent
        if let customThumbnailPath = UserDefaults.standard.string(forKey: "customThumbnail_\(fileName)"),
           FileManager.default.fileExists(atPath: customThumbnailPath) {
            
            // Send custom thumbnail first, then send the video only once the thumbnail
            // transfer completes so the Apple TV always has the thumbnail before the video.
            let thumbnailURL = URL(fileURLWithPath: customThumbnailPath)
            let thumbnailWireName = EclipseShareProtocol.mediaResourceName(
                for: "thumbnail_\(fileName)", mode: mode
            )

            session.sendResource(at: thumbnailURL, withName: thumbnailWireName, toPeer: peer) { [weak self] error in
                if let error = error {
                    self?.logger.error("Custom thumbnail transfer failed: \(error.localizedDescription)")
                } else {
                    self?.logger.info("Custom thumbnail sent successfully")
                }
                // Clean up the temporary thumbnail file
                try? FileManager.default.removeItem(at: thumbnailURL)
                UserDefaults.standard.removeObject(forKey: "customThumbnail_\(fileName)")
                
                // Now send the video itself — only if this transfer is still current.
                DispatchQueue.main.async {
                    guard let self = self, self.transferGeneration == generation else { return }
                    self.beginVideoResourceSend(videoURL, session: session, peer: peer,
                                                generation: generation, mode: mode)
                }
            }
        } else {
            // No custom thumbnail; send the video immediately
            beginVideoResourceSend(videoURL, session: session, peer: peer,
                                   generation: generation, mode: mode)
        }
        
        return true
    }

    /// Performs the actual video resource transfer and wires up progress observation.
    private func beginVideoResourceSend(_ videoURL: URL, session: MCSession, peer: MCPeerID,
                                        generation: UInt64,
                                        mode: EclipseShareProtocol.LibraryMode) {
        guard transferGeneration == generation, !isTransferCancelled else {
            logger.info("Video transfer cancelled before it began")
            return
        }

        let restoreId = sendPendingRestoreIfNeeded(to: peer, via: session)

        let fileName = videoURL.lastPathComponent
        // Keep a full-resolution copy on the phone for external AirPlay presentation
        // (see sendImage for rationale).
        LocalMediaStore.shared.store(fileURL: videoURL, forId: fileName, mode: mode)
        // Replicate to other synced TVs (no progress UI for those).
        fanOutMediaToReplicas(
            url: videoURL,
            id: fileName,
            mode: mode,
            excluding: peer,
            restoreId: restoreId
        )
        let wireName = EclipseShareProtocol.mediaResourceName(for: fileName, mode: mode)
        let progress = session.sendResource(at: videoURL, withName: wireName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self, self.transferGeneration == generation else { return }
                
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

    /// Uploads media the user added while offline to the active Apple TV. Each file that
    /// transfers successfully is removed from `PendingUploadStore`; failures stay queued
    /// for the next connection. The TV adds the items and re-broadcasts its manifest,
    /// which reconciles the companion's optimistic entries.
    ///
    /// Uses a single `transferGeneration` for the whole batch so `cancelCurrentTransfer`
    /// invalidates every outstanding completion without each item cancelling the previous.
    /// Replicas receive the same fan-out as a normal send.
    ///
    /// - Parameter mode: Library bucket the batch belongs to. Captured by the caller so a
    ///   mid-flush display-mode switch cannot remove (or leave) the wrong queue entries.
    func uploadPending(_ items: [(id: String, url: URL)],
                       mode: EclipseShareProtocol.LibraryMode) {
        guard let session = session, let peer = activeTargetPeer, !items.isEmpty else { return }

        transferGeneration &+= 1
        let generation = transferGeneration
        isTransferCancelled = false

        for item in items {
            fanOutMediaToReplicas(url: item.url, id: item.id, mode: mode, excluding: peer)
            let wireName = EclipseShareProtocol.mediaResourceName(for: item.id, mode: mode)
            session.sendResource(at: item.url, withName: wireName, toPeer: peer) { [weak self] error in
                DispatchQueue.main.async {
                    guard let self = self, self.transferGeneration == generation else { return }
                    if let error = error {
                        self.logger.error(
                            "Pending upload failed for \(item.id, privacy: .public): \(error.localizedDescription)"
                        )
                        return
                    }
                    self.logger.info("Uploaded queued item \(item.id, privacy: .public)")
                    Task { @MainActor in
                        PendingUploadStore.shared.remove(id: item.id, mode: mode)
                    }
                }
            }
        }
    }

    /// Fans a just-sent media file out to every connected replica TV (all connected peers
    /// except the active one). No-op unless syncing all.
    ///
    /// Prior in-flight replica sends are left alone — cancelling them on every new fan-out
    /// meant only the most recently sent item reliably arrived on replicas. Finished
    /// progress objects are pruned so the array cannot grow unbounded.
    private func fanOutMediaToReplicas(
        url: URL,
        id: String,
        mode: EclipseShareProtocol.LibraryMode,
        excluding active: MCPeerID,
        restoreId: String? = nil
    ) {
        guard syncAllEnabled, let session = session else { return }
        pruneFinishedReplicaTransfers()
        for peer in session.connectedPeers where peer != active {
            if let restoreId {
                sendRestoreEnvelope(id: restoreId, to: peer, via: session)
            }
            if let progress = sendMedia(at: url, id: id, mode: mode, to: peer) {
                replicaTransferProgress.append(progress)
            }
        }
    }

    /// Drops completed or cancelled replica progress so fan-out tracking stays bounded.
    private func pruneFinishedReplicaTransfers() {
        replicaTransferProgress.removeAll { $0.isFinished || $0.isCancelled }
    }

    /// If a re-send was requested, tells the active TV the upcoming resource restores a
    /// purged item, then clears the flag. Returns the id so replicas can get the same
    /// envelope before their resource.
    @discardableResult
    private func sendPendingRestoreIfNeeded(
        to peer: MCPeerID,
        via session: MCSession
    ) -> String? {
        guard let restoreId = pendingRestoreId else { return nil }
        guard sendRestoreEnvelope(id: restoreId, to: peer, via: session) else {
            return nil
        }
        // Clear only once the TV has actually been told. Clearing up front meant a
        // failed send consumed the intent, and the resource that followed was filed
        // as a brand-new item instead of restoring the purged one.
        pendingRestoreId = nil
        return restoreId
    }

    /// Sends a `restore_item` envelope to one peer ahead of its media resource.
    @discardableResult
    private func sendRestoreEnvelope(
        id: String,
        to peer: MCPeerID,
        via session: MCSession
    ) -> Bool {
        let envelope = EclipseShareEnvelope.restoreItem(id: id)
            .withLibraryMode(ExternalOutputSettings.libraryMode)
        guard let data = envelope.encoded() else {
            logger.error("Could not encode restore_item for \(id, privacy: .public)")
            return false
        }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            logger.info("Sent restore_item for id: \(id, privacy: .public)")
            return true
        } catch {
            logger.error("restore_item send failed: \(error.localizedDescription)")
            return false
        }
    }
}
