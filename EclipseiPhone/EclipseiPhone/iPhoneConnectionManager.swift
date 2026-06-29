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

    /// When false, the manager's own automatic reconnection behaviors are suspended:
    /// it won't re-browse or re-invite on app-active, browser failure, or disconnect.
    /// Set to false while the user is using the app offline ("paused"); flipped back to
    /// true the moment they ask to connect again. Does not tear down an existing session.
    var autoConnectEnabled = true
    
    private var currentTransferTask: Progress?
    private var isTransferCancelled = false
    private var isTransferringVideo = false
    private var currentProgress: Progress?

    /// Tracks in-flight invitations (keyed by peer) so the auto-connect timer and
    /// app-active handlers don't fire overlapping invitations to the same peer.
    /// Overlapping invites make MultipeerConnectivity tear down and restart the handshake
    /// (the TV's accept fails to deliver and channels are abandoned), which can leave the
    /// connection stuck. A dictionary (rather than a single peer) supports inviting
    /// several Apple TVs at once when "keep all in sync" is enabled.
    private var pendingInvites: [MCPeerID: Date] = [:]
    /// Matches the invitation timeout below; after this, a stale attempt may be retried.
    private let inviteTimeout: TimeInterval = 60

    /// The peer whose library the companion UI mirrors. This is the first peer to connect
    /// and is unchanged when additional "sync replica" Apple TVs connect under
    /// `syncAllEnabled`. Library mirroring, playback control, and the header all follow
    /// this peer.
    private(set) var activePeer: MCPeerID?

    private let syncAllKey = "EclipseTV.companion.syncAllTVs"

    /// When true, library mutations fan out to every connected Apple TV and the manager
    /// keeps additional discovered TVs connected as sync replicas. The active TV still
    /// drives the mirrored UI. Backed by the same UserDefaults key the Settings toggle writes.
    var syncAllEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: syncAllKey) }
        set {
            UserDefaults.standard.set(newValue, forKey: syncAllKey)
            if newValue {
                inviteAllDiscoveredPeersForSync()
            } else {
                disconnectSyncReplicas()
            }
        }
    }

    /// Coordinates catching newly connected replica TVs up to the active library.
    weak var syncCoordinator: MultiTVSyncCoordinator?

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
        // Respect the user's choice to stay offline; don't silently reconnect.
        guard autoConnectEnabled else {
            logger.debug("App became active but auto-connect is paused; staying offline")
            return
        }
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
        
        // Don't invite a second peer while connected to another, UNLESS we're keeping all
        // Apple TVs in sync (in which case additional TVs are connected as replicas).
        if session.connectedPeers.isEmpty == false && !syncAllEnabled {
            logger.info("[Eclipse:CONN] iPhone skipping invite, already connected to another peer")
            return
        }

        // Don't start a second invitation to the SAME peer while one is still negotiating.
        // Overlapping invites cause MultipeerConnectivity to abandon the in-progress
        // handshake. Invitations to different peers may proceed concurrently (for sync).
        if let startedAt = pendingInvites[peer], Date().timeIntervalSince(startedAt) < inviteTimeout {
            logger.info("[Eclipse:CONN] iPhone skipping invite to \(peer.displayName, privacy: .public): invitation already in flight")
            return
        }

        // Increase timeout to 60 seconds and present the shared handshake token so the
        // Apple TV can authenticate this client.
        let context = "\(handshakeToken)-iPhone".data(using: .utf8)
        pendingInvites[peer] = Date()
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 60)
        logger.info("[Eclipse:CONN] iPhone invited peer: \(peer.displayName, privacy: .public) (timeout 60s)")
    }

    /// Clears in-flight invitation bookkeeping for a peer once its attempt resolves.
    private func clearPendingInvite(for peer: MCPeerID) {
        pendingInvites[peer] = nil
    }

    /// Clears all in-flight invitation bookkeeping.
    private func clearAllPendingInvites() {
        pendingInvites.removeAll()
    }
    
    func disconnect() {
        clearAllPendingInvites()
        activePeer = nil
        session?.disconnect()
        logger.info("Disconnected session")
    }

    /// Switches the active connection to `peer`. If currently connected to a different
    /// Apple TV, tears that down first (only one peer is connected at a time), then
    /// invites the requested peer.
    func switchToPeer(_ peer: MCPeerID) {
        // Already connected (possibly as a sync replica): just promote it to the active TV.
        if session?.connectedPeers.contains(peer) == true {
            logger.info("[Eclipse:CONN] iPhone already connected to requested peer: \(peer.displayName, privacy: .public)")
            promoteToActive(peer)
            return
        }
        // When keeping all TVs in sync we keep the other connections alive; otherwise the
        // single active connection is torn down before switching.
        if session?.connectedPeers.isEmpty == false && !syncAllEnabled {
            logger.info("[Eclipse:CONN] iPhone switching peers, disconnecting current session")
            session?.disconnect()
            activePeer = nil
        }
        clearPendingInvite(for: peer)
        invitePeer(peer)
    }

    /// Makes an already-connected peer the active (mirrored) TV without disturbing other
    /// connected sync replicas.
    private func promoteToActive(_ peer: MCPeerID) {
        guard activePeer != peer else { return }
        activePeer = peer
        Task { @MainActor in
            TVLibraryStore.shared.setActiveTV(peer.displayName)
            TVLibraryStore.shared.setOnline(true)
        }
        DispatchQueue.main.async {
            self.delegate?.connectionManager(self, didConnectToPeer: peer)
        }
    }

    /// Invites every discovered Apple TV that isn't already connected, so they join as
    /// sync replicas. Only the Eclipse Apple TV app advertises `eclipse-share`, so all
    /// discovered peers are Eclipse TVs.
    func inviteAllDiscoveredPeersForSync() {
        guard syncAllEnabled else { return }
        if !isBrowsing { startBrowsing() }
        for peer in discoveredPeers where session?.connectedPeers.contains(peer) != true {
            invitePeer(peer)
        }
    }

    /// Disconnects all peers except the active TV, restoring single-TV behavior when the
    /// user turns "keep all in sync" off. MultipeerConnectivity has no per-peer disconnect,
    /// so this is a no-op when more than the active peer is connected is handled by the TVs
    /// timing out; in practice we simply stop inviting replicas and let them drop.
    func disconnectSyncReplicas() {
        // There's no public API to drop a single peer from an MCSession; replicas are left
        // to time out naturally once we stop sending to or inviting them. New mutations
        // will only target the active peer (see syncTargetPeers).
        logger.info("[Eclipse:CONN] Sync disabled; replicas will no longer receive updates")
    }

    /// Asks the Apple TV to make the item with the given id (file name) live/fullscreen.
    @discardableResult
    func sendPlayRequest(id: String) -> Bool {
        return sendCommand(.playRequest(id: id), description: "play request")
    }

    /// Asks the Apple TV to delete the item with the given id. Broadcast to all synced
    /// TVs so their libraries stay matched.
    @discardableResult
    func sendDeleteRequest(id: String) -> Bool {
        return sendCommand(.deleteItem(id: id), description: "delete request", broadcast: true)
    }

    /// Asks the Apple TV to move the item with the given id to a new index. Broadcast to
    /// all synced TVs.
    @discardableResult
    func sendMoveRequest(id: String, toIndex: Int) -> Bool {
        return sendCommand(.moveItem(id: id, toIndex: toIndex), description: "move request", broadcast: true)
    }

    /// Asks the Apple TV to reorder its live library to match `orderedIds` exactly.
    /// Used when saving a drag-and-drop arrangement made on the companion. Broadcast to
    /// all synced TVs.
    @discardableResult
    func sendReorderRequest(orderedIds: [String]) -> Bool {
        return sendCommand(.reorderItems(orderedIds: orderedIds), description: "reorder request", broadcast: true)
    }

    /// Asks the Apple TV to change a per-item video setting. Nil fields are left as-is.
    /// Broadcast to all synced TVs.
    @discardableResult
    func sendVideoSetting(id: String, isLooping: Bool?, isMuted: Bool?) -> Bool {
        return sendCommand(.setVideoSetting(id: id, isLooping: isLooping, isMuted: isMuted),
                           description: "video setting", broadcast: true)
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

    /// Sends a control envelope. When `broadcast` is true and "keep all in sync" is on,
    /// the message goes to every connected Apple TV; otherwise it targets only the active
    /// TV (preserving single-TV behavior for live-selection and playback commands).
    @discardableResult
    private func sendCommand(_ envelope: EclipseShareEnvelope, description: String, broadcast: Bool = false) -> Bool {
        guard let session = session, let data = envelope.encoded() else {
            logger.error("Cannot send \(description): no session or failed to encode")
            return false
        }
        let peers = syncTargetPeers(broadcast: broadcast, in: session)
        guard !peers.isEmpty else {
            logger.error("Cannot send \(description): no active session or peer")
            return false
        }
        do {
            try session.send(data, toPeers: peers, with: .reliable)
            logger.info("Sent \(description) to \(peers.count) peer(s)")
            return true
        } catch {
            logger.error("Failed to send \(description): \(error.localizedDescription)")
            return false
        }
    }

    /// Resolves the peers a message should target: every connected TV for broadcast
    /// mutations while syncing all, otherwise just the active TV (falling back to the
    /// first connected peer for backwards compatibility).
    private func syncTargetPeers(broadcast: Bool, in session: MCSession) -> [MCPeerID] {
        if broadcast && syncAllEnabled { return session.connectedPeers }
        if let active = activePeer, session.connectedPeers.contains(active) { return [active] }
        if let first = session.connectedPeers.first { return [first] }
        return []
    }

    /// The peer the UI mirrors / sends user-initiated transfers to: the active TV when
    /// connected, else the first connected peer.
    private var activeTargetPeer: MCPeerID? {
        if let active = activePeer, session?.connectedPeers.contains(active) == true { return active }
        return session?.connectedPeers.first
    }

    /// Sends a control envelope to one specific peer (used by the sync coordinator to
    /// catch a replica TV up). Returns false if the peer isn't connected.
    @discardableResult
    func sendEnvelope(_ envelope: EclipseShareEnvelope, to peer: MCPeerID) -> Bool {
        guard let session = session, session.connectedPeers.contains(peer),
              let data = envelope.encoded() else { return false }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            return true
        } catch {
            logger.error("Failed to send envelope to \(peer.displayName, privacy: .public): \(error.localizedDescription)")
            return false
        }
    }

    /// Sends a media file to one specific peer without progress UI (used by the sync
    /// coordinator to replay the library to a replica TV).
    func sendMedia(at url: URL, id: String, to peer: MCPeerID) {
        guard let session = session, session.connectedPeers.contains(peer) else { return }
        session.sendResource(at: url, withName: id, toPeer: peer) { [weak self] error in
            if let error = error {
                self?.logger.error("Replica media send failed for \(id, privacy: .public): \(error.localizedDescription)")
            }
        }
    }

    /// The connected peer with the given display name, if any. Lets the (name-based) sync
    /// coordinator address a specific TV without holding `MCPeerID` references.
    private func connectedPeer(named name: String) -> MCPeerID? {
        session?.connectedPeers.first { $0.displayName == name }
    }

    /// Whether the named TV is currently connected.
    func isConnectedToPeerNamed(_ name: String) -> Bool {
        connectedPeer(named: name) != nil
    }

    /// Replays a full library to one TV (used by the sync coordinator to catch a replica
    /// up). Sends every media file, then — once all transfers finish — a single reorder so
    /// the replica's order matches. Reordering after the transfers ensures the ids are
    /// present on the TV when the reorder is applied. `completion` reports whether anything
    /// was actually sent.
    func replayLibrary(_ items: [(id: String, url: URL)],
                       orderedIds: [String],
                       toPeerNamed name: String,
                       completion: @escaping (Bool) -> Void) {
        guard let session = session, let peer = connectedPeer(named: name), !items.isEmpty else {
            completion(false)
            return
        }
        let group = DispatchGroup()
        for item in items {
            group.enter()
            session.sendResource(at: item.url, withName: item.id, toPeer: peer) { [weak self] error in
                if let error = error {
                    self?.logger.error("Replay send failed for \(item.id, privacy: .public): \(error.localizedDescription)")
                }
                group.leave()
            }
        }
        group.notify(queue: .main) { [weak self] in
            self?.sendEnvelope(.reorderItems(orderedIds: orderedIds), to: peer)
            completion(true)
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

        // When keeping all Apple TVs in sync, connect every newly discovered TV (the
        // first to connect becomes the active/mirrored TV; the rest are sync replicas).
        if syncAllEnabled, session?.connectedPeers.contains(peerID) != true {
            invitePeer(peerID)
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
                if let self = self, self.autoConnectEnabled, !self.isBrowsing {
                    self.startBrowsing()
                }
            }
        } else {
            logger.debug("General browser error, retrying in 5 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                if let self = self, self.autoConnectEnabled, !self.isBrowsing {
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
            clearPendingInvite(for: peerID)
            resetRetryCount()

            // The first peer to connect becomes the active (mirrored) TV; any subsequent
            // ones are sync replicas under "keep all in sync".
            let isPrimary = (activePeer == nil)
            if isPrimary {
                activePeer = peerID
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
                activePeer = nil
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
