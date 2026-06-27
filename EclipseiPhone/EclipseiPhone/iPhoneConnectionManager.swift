import UIKit
import MultipeerConnectivity
import os.log

protocol iPhoneConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: iPhoneConnectionManager, didFindPeer peer: MCPeerID)
    func connectionManager(_ manager: iPhoneConnectionManager, didLosePeer peer: MCPeerID)
    func connectionManager(_ manager: iPhoneConnectionManager, didConnectToPeer peer: MCPeerID)
    func connectionManager(_ manager: iPhoneConnectionManager, didDisconnectFromPeer peer: MCPeerID)
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveConfirmationFromPeer peer: MCPeerID)
    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateVideoTransferProgress progress: Double)
    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateImageTransferProgress progress: Double)
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveMoveModeState enabled: Bool)
    func connectionManager(_ manager: iPhoneConnectionManager, didFailTransferIsVideo isVideo: Bool, error: Error?)
}

class iPhoneConnectionManager: NSObject {
    // MARK: - Properties
    
    private let serviceType = "eclipse-share" // MUST MATCH EXACTLY on both devices

    /// Shared handshake token used to authenticate with the Apple TV. MUST MATCH the
    /// value in the Apple TV app's `ConnectionManager`.
    private let handshakeToken = "EclipseShare/v1"

    private(set) var session: MCSession? // Allow read-only access from outside
    private var browser: MCNearbyServiceBrowser?
    private let peerID: MCPeerID
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ConnectionManager")
    
    weak var delegate: iPhoneConnectionManagerDelegate?
    var isBrowsing: Bool = false
    var discoveredPeers = [MCPeerID]() // Track discovered peers for auto-connection
    
    private var currentTransferTask: Progress?
    private var isTransferCancelled = false
    private var isTransferringVideo = false
    private var currentProgress: Progress?

    /// Tracks an in-flight invitation so the auto-connect timer and app-active handlers
    /// don't fire overlapping invitations to the same peer. Overlapping invites make
    /// MultipeerConnectivity tear down and restart the handshake (the TV's accept fails
    /// to deliver and channels are abandoned), which can leave the connection stuck.
    private var pendingInvitePeer: MCPeerID?
    private var pendingInviteStartedAt: Date?
    /// Matches the invitation timeout below; after this, a stale attempt may be retried.
    private let inviteTimeout: TimeInterval = 60

    /// When set, the next media send is a re-send of a purged Apple TV item. A
    /// `restore_item` envelope (carrying the original item id) is sent just before the
    /// resource so the TV can restore it into its original slot. Cleared after sending.
    var pendingRestoreId: String?
    
    // Keep track of AppleTV's move mode state
    private(set) var isAppleTVInMoveMode = false
    
    // Connection retry mechanism
    private var retryCount = 0
    private let maxRetries = 3
    private var retryTimer: Timer?
    
    // MARK: - Initialization
    
    override init() {
        // Log the device name we're using
        let deviceName = UIDevice.current.name
        self.peerID = MCPeerID(displayName: deviceName)
        super.init()
        logger.debug("Initializing iPhoneConnectionManager with device name: \(deviceName, privacy: .public)")
        setupMultipeerConnectivity()
        
        // Register for notifications
        NotificationCenter.default.addObserver(self,
                                               selector: #selector(handleAppDidBecomeActive),
                                               name: UIApplication.didBecomeActiveNotification,
                                               object: nil)
    }
    
    deinit {
        cleanupCurrentProgress()
        retryTimer?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }
    
    // MARK: - Private Methods
    
    private func cleanupCurrentProgress() {
        if let progress = currentProgress {
            progress.removeObserver(self, forKeyPath: #keyPath(Progress.fractionCompleted))
            currentProgress = nil
        }
    }
    
    // MARK: - Notification Handlers
    
    @objc private func handleAppDidBecomeActive() {
        logger.debug("App became active, ensuring connection")
        // If we have a peer but aren't connected, try to reconnect
        if let selectedPeer = discoveredPeers.first, session?.connectedPeers.isEmpty == true {
            logger.debug("Trying to reconnect to \(selectedPeer.displayName, privacy: .public)")
            invitePeer(selectedPeer)
        } else if discoveredPeers.isEmpty && !isBrowsing {
            // If we don't have any discovered peers, start browsing
            startBrowsing()
        }
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        logger.debug("Setting up Multipeer Connectivity with service type: \(self.serviceType, privacy: .public)")
        logger.debug("Peer ID: \(self.peerID.displayName, privacy: .public)")
        
        // Create session with required encryption for all peer-to-peer traffic
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Create browser
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        logger.debug("Browser created successfully")
    }
    
    // MARK: - Public Methods
    
    func isConnectedToPeer(_ peer: MCPeerID) -> Bool {
        return session?.connectedPeers.contains(peer) == true
    }
    
    func startBrowsing() {
        logger.debug("Starting browsing for peers")
        
        // Check if browser exists
        if browser == nil {
            logger.error("Browser is nil! Recreating...")
            setupMultipeerConnectivity()
        }
        
        discoveredPeers.removeAll()
        browser?.startBrowsingForPeers()
        isBrowsing = true
        logger.info("[Eclipse:CONN] iPhone started browsing for service '\(self.serviceType, privacy: .public)' as '\(self.peerID.displayName, privacy: .public)'")
        
        // Add verification after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyBrowsing()
        }
    }
    
    private func verifyBrowsing() {
        logger.debug("Verifying browsing status: isBrowsing=\(self.isBrowsing), browserExists=\(self.browser != nil), peers=\(self.discoveredPeers.count)")
    }
    
    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        isBrowsing = false
        logger.info("Stopped browsing for peers")
    }
    
    func invitePeer(_ peer: MCPeerID) {
        guard let session = session else {
            logger.error("Cannot invite peer: session is nil")
            return
        }
        
        // Don't invite if we're already connected to this peer
        if session.connectedPeers.contains(peer) {
            logger.info("[Eclipse:CONN] iPhone skipping invite, already connected to: \(peer.displayName, privacy: .public)")
            return
        }
        
        // Don't invite if we're currently connecting to this peer
        if session.connectedPeers.isEmpty == false {
            logger.info("[Eclipse:CONN] iPhone skipping invite, already connected to another peer")
            return
        }

        // Don't start a second invitation while one is still negotiating. Overlapping
        // invites cause MultipeerConnectivity to abandon the in-progress handshake.
        if let pendingPeer = pendingInvitePeer,
           let startedAt = pendingInviteStartedAt,
           Date().timeIntervalSince(startedAt) < inviteTimeout {
            logger.info("[Eclipse:CONN] iPhone skipping invite to \(peer.displayName, privacy: .public): invitation already in flight to \(pendingPeer.displayName, privacy: .public)")
            return
        }

        // Increase timeout to 60 seconds and present the shared handshake token so the
        // Apple TV can authenticate this client.
        let context = "\(handshakeToken)-iPhone".data(using: .utf8)
        pendingInvitePeer = peer
        pendingInviteStartedAt = Date()
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 60)
        logger.info("[Eclipse:CONN] iPhone invited peer: \(peer.displayName, privacy: .public) (timeout 60s)")
    }

    /// Clears any in-flight invitation bookkeeping once an attempt resolves.
    private func clearPendingInvite() {
        pendingInvitePeer = nil
        pendingInviteStartedAt = nil
    }
    
    func disconnect() {
        clearPendingInvite()
        session?.disconnect()
        logger.info("Disconnected session")
    }

    /// Switches the active connection to `peer`. If currently connected to a different
    /// Apple TV, tears that down first (only one peer is connected at a time), then
    /// invites the requested peer.
    func switchToPeer(_ peer: MCPeerID) {
        if session?.connectedPeers.contains(peer) == true {
            logger.info("[Eclipse:CONN] iPhone already connected to requested peer: \(peer.displayName, privacy: .public)")
            return
        }
        if session?.connectedPeers.isEmpty == false {
            logger.info("[Eclipse:CONN] iPhone switching peers, disconnecting current session")
            session?.disconnect()
        }
        clearPendingInvite()
        invitePeer(peer)
    }

    /// Asks the Apple TV to make the item with the given id (file name) live/fullscreen.
    @discardableResult
    func sendPlayRequest(id: String) -> Bool {
        return sendCommand(.playRequest(id: id), description: "play request")
    }

    /// Asks the Apple TV to delete the item with the given id.
    @discardableResult
    func sendDeleteRequest(id: String) -> Bool {
        return sendCommand(.deleteItem(id: id), description: "delete request")
    }

    /// Asks the Apple TV to move the item with the given id to a new index.
    @discardableResult
    func sendMoveRequest(id: String, toIndex: Int) -> Bool {
        return sendCommand(.moveItem(id: id, toIndex: toIndex), description: "move request")
    }

    /// Asks the Apple TV to reorder its live library to match `orderedIds` exactly.
    /// Used when saving a drag-and-drop arrangement made on the companion.
    @discardableResult
    func sendReorderRequest(orderedIds: [String]) -> Bool {
        return sendCommand(.reorderItems(orderedIds: orderedIds), description: "reorder request")
    }

    /// Asks the Apple TV to change a per-item video setting. Nil fields are left as-is.
    @discardableResult
    func sendVideoSetting(id: String, isLooping: Bool?, isMuted: Bool?) -> Bool {
        return sendCommand(.setVideoSetting(id: id, isLooping: isLooping, isMuted: isMuted),
                           description: "video setting")
    }

    /// Sends a remote playback command for the live video. `position` is the absolute
    /// target for `.seek` or the relative delta for `.skip` (seconds).
    @discardableResult
    func sendPlaybackCommand(action: EclipseShareProtocol.PlaybackAction, position: Double?) -> Bool {
        return sendCommand(.playbackCommand(action: action, position: position), description: "playback command")
    }

    /// Configures the TV's read-only remote albums from a short account code. The TV
    /// composes the manifest URL from it and syncs all of the account's albums.
    @discardableResult
    func sendSetAccount(code: String) -> Bool {
        return sendCommand(.setAccount(code: code), description: "set account")
    }

    private func sendCommand(_ envelope: EclipseShareEnvelope, description: String) -> Bool {
        guard let session = session, let peer = session.connectedPeers.first else {
            logger.error("Cannot send \(description): no active session or peer")
            return false
        }
        guard let data = envelope.encoded() else { return false }

        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            logger.info("Sent \(description)")
            return true
        } catch {
            logger.error("Failed to send \(description): \(error.localizedDescription)")
            return false
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

    func sendImage(at imageURL: URL) -> Bool {
        guard let session = session, let peer = session.connectedPeers.first else {
            logger.error("Cannot send image: No active session or peer")
            return false
        }

        isTransferCancelled = false
        isTransferringVideo = false

        // Clean up any existing progress observer before starting new transfer
        cleanupCurrentProgress()

        sendPendingRestoreIfNeeded(to: peer, via: session)

        let fileName = imageURL.lastPathComponent
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

    // Add image progress observer
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
        guard let session = session, let peer = session.connectedPeers.first else {
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
    
    // MARK: - Connection Retry Logic
    
    private func scheduleReconnectAttempt(to peer: MCPeerID) {
        // Cancel any existing retry timer
        retryTimer?.invalidate()
        
        guard retryCount < maxRetries else {
            logger.error("Max retry attempts reached for peer: \(peer.displayName, privacy: .public)")
            retryCount = 0
            return
        }
        
        retryCount += 1
        let delay = TimeInterval(retryCount * 2) // Exponential backoff: 2s, 4s, 6s
        
        logger.debug("Scheduling reconnect attempt \(self.retryCount)/\(self.maxRetries) in \(delay)s")
        
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            self.logger.debug("Retry attempt \(self.retryCount) to reconnect to \(peer.displayName, privacy: .public)")
            self.invitePeer(peer)
        }
    }
    
    private func resetRetryCount() {
        retryCount = 0
        retryTimer?.invalidate()
        retryTimer = nil
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension iPhoneConnectionManager: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String : String]?) {
        logger.info("[Eclipse:CONN] iPhone found peer: \(peerID.displayName, privacy: .public)")
        
        // Track discovered peer
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
        
        DispatchQueue.main.async {
            self.delegate?.connectionManager(self, didFindPeer: peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("[Eclipse:CONN] iPhone lost peer: \(peerID.displayName, privacy: .public)")
        
        if let index = discoveredPeers.firstIndex(of: peerID) {
            discoveredPeers.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.delegate?.connectionManager(self, didLosePeer: peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        logger.error("[Eclipse:CONN] iPhone FAILED to start browsing: \(error.localizedDescription, privacy: .public)")
        
        // Handle specific error types and retry
        if error.localizedDescription.contains("busy") || error.localizedDescription.contains("in use") {
            logger.debug("Browser service appears busy, waiting 10 seconds before retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                if let self = self, !self.isBrowsing {
                    self.startBrowsing()
                }
            }
        } else {
            logger.debug("General browser error, retrying in 5 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                if let self = self, !self.isBrowsing {
                    self.startBrowsing()
                }
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension iPhoneConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        logger.debug("Peer \(peerID.displayName, privacy: .public) changed state to: \(state.rawValue)")
        
        switch state {
        case .connected:
            logger.info("[Eclipse:CONN] iPhone CONNECTED to peer: \(peerID.displayName, privacy: .public)")
            clearPendingInvite()
            // Stop browsing once connected to avoid duplicate connections
            stopBrowsing()
            // Reset retry count on successful connection
            resetRetryCount()
            Task { @MainActor in
                // Point the store at this TV's library bucket *before* its manifest
                // arrives so the incoming manifest/thumbnails land in the right cache.
                TVLibraryStore.shared.setActiveTV(peerID.displayName)
                TVLibraryStore.shared.setOnline(true)
            }
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didConnectToPeer: peerID)
            }
            
        case .connecting:
            logger.info("[Eclipse:CONN] iPhone connecting to peer: \(peerID.displayName, privacy: .public)")
            
        case .notConnected:
            logger.info("[Eclipse:CONN] iPhone NOT connected to peer: \(peerID.displayName, privacy: .public)")
            // The attempt resolved (failed/timed out/dropped); allow a fresh invitation.
            clearPendingInvite()
            // Keep the cached library but mark it offline; it refreshes on reconnect.
            Task { @MainActor in
                TVLibraryStore.shared.setOnline(false)
            }
            // Restart browsing if we were connected but got disconnected
            if discoveredPeers.contains(peerID) {
                startBrowsing()
                // Try to reconnect with exponential backoff
                scheduleReconnectAttempt(to: peerID)
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
                isAppleTVInMoveMode = true
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveMoveModeState: true)
                }
                return
            }
            
            if message == "MOVE_MODE_DISABLED" {
                logger.debug("Apple TV exited move mode")
                isAppleTVInMoveMode = false
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
