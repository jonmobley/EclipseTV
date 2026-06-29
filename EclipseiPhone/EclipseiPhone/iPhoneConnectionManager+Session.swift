// iPhoneConnectionManager+Session.swift
import UIKit
import MultipeerConnectivity

// MARK: - MCSessionDelegate

/// Session state handling (active/replica promotion, reconnect) and inbound message
/// routing: confirmations, move-mode signals, thumbnails, and library-control envelopes.
extension iPhoneConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        logger.debug("Peer \(peerID.displayName, privacy: .public) changed state to: \(state.rawValue)")
        
        switch state {
        case .connected:
            logger.info("[Eclipse:CONN] iPhone CONNECTED to peer: \(peerID.displayName, privacy: .public)")
            clearPendingInvite(for: peerID)
            resetRetryCount()

            // The first peer to connect becomes the active (mirrored) TV; any subsequent
            // ones are sync replicas under "keep all in sync".
            let isPrimary = (activePeer == nil)
            if isPrimary {
                setActivePeer(peerID)
                // Keep browsing while gathering replicas; otherwise stop to avoid
                // duplicate connections.
                if !syncAllEnabled { stopBrowsing() }
                Task { @MainActor in
                    // Point the store at this TV's library bucket *before* its manifest
                    // arrives so the incoming manifest/thumbnails land in the right cache.
                    TVLibraryStore.shared.setActiveTV(peerID.displayName)
                    TVLibraryStore.shared.setOnline(true)
                }
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didConnectToPeer: peerID)
                }
            } else {
                logger.info("[Eclipse:CONN] Connected sync replica: \(peerID.displayName, privacy: .public)")
            }

            // Keep gathering replicas and catch this TV up to the active library.
            if syncAllEnabled {
                let name = peerID.displayName
                if !isPrimary {
                    Task { @MainActor in self.syncCoordinator?.peerConnected(named: name) }
                }
                inviteAllDiscoveredPeersForSync()
            }
            
        case .connecting:
            logger.info("[Eclipse:CONN] iPhone connecting to peer: \(peerID.displayName, privacy: .public)")
            
        case .notConnected:
            logger.info("[Eclipse:CONN] iPhone NOT connected to peer: \(peerID.displayName, privacy: .public)")
            // The attempt resolved (failed/timed out/dropped); allow a fresh invitation.
            clearPendingInvite(for: peerID)

            // If the active TV dropped, go offline and let the normal reconnect flow
            // re-establish a primary. Replica drops don't affect the mirrored UI.
            let wasActive = (activePeer == peerID)
            if wasActive {
                setActivePeer(nil)
                Task { @MainActor in
                    TVLibraryStore.shared.setOnline(false)
                }
            }
            // Restart browsing if we were connected but got disconnected — unless the
            // user has paused auto-connect to use the app offline. Only the active peer
            // gets the exponential-backoff reconnect; replicas are re-invited on
            // rediscovery via inviteAllDiscoveredPeersForSync.
            if autoConnectEnabled, discoveredPeers.contains(peerID) {
                startBrowsing()
                if wasActive {
                    scheduleReconnectAttempt(to: peerID)
                }
            }
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didDisconnectFromPeer: peerID)
            }
            
        @unknown default:
            logger.error("Unknown session state: \(state.rawValue)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Eclipse library-mirroring control messages are tagged JSON envelopes; handle
        // them before the plain-string confirmations below.
        if let envelope = EclipseShareEnvelope.decode(from: data) {
            handleControlEnvelope(envelope)
            return
        }

        // Check if this is a confirmation message
        if let message = String(data: data, encoding: .utf8) {
            if message == "IMAGE_RECEIVED" || message == "VIDEO_RECEIVED" {
                logger.debug("Received confirmation from Apple TV: \(message, privacy: .public)")
                // Notify delegate that media was received by Apple TV
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveConfirmationFromPeer: peerID)
                }
                return
            }

            if message == "IMAGE_ERROR" || message == "VIDEO_ERROR" {
                logger.debug("Received error from Apple TV: \(message, privacy: .public)")
                let isVideo = (message == "VIDEO_ERROR")
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didFailTransferIsVideo: isVideo, error: nil)
                }
                return
            }
            
            // Handle move mode status messages
            if message == "MOVE_MODE_ENABLED" {
                logger.debug("Apple TV entered move mode")
                setAppleTVInMoveMode(true)
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveMoveModeState: true)
                }
                return
            }
            
            if message == "MOVE_MODE_DISABLED" {
                logger.debug("Apple TV exited move mode")
                setAppleTVInMoveMode(false)
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveMoveModeState: false)
                }
                return
            }
        }
        
        // Handle other data types if needed
        logger.debug("Received data from peer: \(peerID.displayName, privacy: .public)")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this app
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this app
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // The only resources the Apple TV sends us are library thumbnails.
        guard error == nil,
              let localURL = localURL,
              let id = EclipseShareProtocol.itemId(fromThumbnailResourceName: resourceName) else {
            return
        }

        if let image = UIImage(contentsOfFile: localURL.path) {
            Task { @MainActor in
                TVLibraryStore.shared.setThumbnail(image, forId: id)
            }
        }

        try? FileManager.default.removeItem(at: localURL)
    }

    // MARK: - Control Message Routing

    /// Routes a decoded library-mirroring envelope into the shared `TVLibraryStore`.
    private func handleControlEnvelope(_ envelope: EclipseShareEnvelope) {
        switch envelope.kind {
        case .libraryManifest:
            let items = envelope.items ?? []
            let currentId = envelope.currentId
            Task { @MainActor in
                TVLibraryStore.shared.updateManifest(items: items, currentId: currentId)
            }
        case .currentChanged:
            let currentId = envelope.currentId
            Task { @MainActor in
                TVLibraryStore.shared.updateCurrentId(currentId)
            }
        case .playbackStatus:
            let currentId = envelope.currentId
            let isPlaying = envelope.isPlaying ?? false
            let position = envelope.position ?? 0
            let duration = envelope.playbackDuration ?? 0
            Task { @MainActor in
                TVLibraryStore.shared.updatePlayback(currentId: currentId, isPlaying: isPlaying,
                                                     position: position, duration: duration)
            }
        case .playRequest, .setVideoSetting, .deleteItem, .moveItem, .reorderItems, .restoreItem, .playbackCommand, .setAccount, .none:
            // These are iPhone -> TV commands; ignore if ever echoed back to us.
            break
        }
    }
}
