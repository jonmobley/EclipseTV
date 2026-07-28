//
//  ConnectionManager.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import MultipeerConnectivity
import os.log

protocol ConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: ConnectionManager, didReceiveImageAt path: String)
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoAt path: String)
    func connectionManager(_ manager: ConnectionManager, didUpdateConnectionState connected: Bool, with peer: MCPeerID?)
    /// The companion requested that the item with the given id (file name) be made live.
    func connectionManager(_ manager: ConnectionManager, didReceivePlayRequestForId id: String)
    /// The companion requested deletion of the item with the given id.
    func connectionManager(_ manager: ConnectionManager, didReceiveDeleteRequestForId id: String)
    /// The companion requested moving the item with the given id to a new index.
    func connectionManager(_ manager: ConnectionManager, didReceiveMoveRequestForId id: String, toIndex: Int)
    /// The companion saved a drag-and-drop arrangement: reorder the live library so its
    /// item ids (file names) match `orderedIds`.
    func connectionManager(_ manager: ConnectionManager, didReceiveReorderRequest orderedIds: [String])
    /// The companion requested a per-item video setting change. Nil fields are unchanged.
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoSettingForId id: String, isLooping: Bool?, isMuted: Bool?)
    /// A purged item was just re-sent: the freshly received file is at `newPath` and the
    /// unavailable ledger entry keyed by `ledgerId` (the original file name) should be
    /// cleared and the new item moved back into its original slot.
    func connectionManager(_ manager: ConnectionManager, didRestoreItemForLedgerId ledgerId: String, newPath: String)
    /// The companion requested a remote playback action for the live video. `position`
    /// is the absolute target for `.seek` or the relative delta for `.skip` (seconds).
    func connectionManager(_ manager: ConnectionManager, didReceivePlaybackCommand action: EclipseShareProtocol.PlaybackAction, position: Double?)
    /// The companion configured the read-only remote albums from an account `code`.
    func connectionManager(_ manager: ConnectionManager, didReceiveSetAccountCode code: String)
}

class ConnectionManager: NSObject {
    // MARK: - Properties
    
    private let serviceType = "eclipse-share" // MUST MATCH EXACTLY on both devices

    /// Allowlist + current on-screen pairing PIN.
    private let pairedStore = PairedPeerStore.shared

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private let peerID: MCPeerID
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ConnectionManager")
    
    weak var delegate: ConnectionManagerDelegate?

    /// Drives library mirroring to the companion. Notified when a peer connects so it
    /// can push a full manifest + thumbnails.
    weak var librarySync: TVLibrarySync?

    private var receivedImageCount = 0
    private var isAdvertising = false

    /// When a companion re-sends a purged item, it first sends a `restore_item` envelope
    /// naming the original item (ledger id). The very next media resource is treated as
    /// that restore. Carries an expiry so a stale request can't hijack an unrelated send.
    /// Accessed only on the `MCSession` delegate queue.
    private var pendingRestore: (ledgerId: String, expires: Date)?
    private let restoreWindow: TimeInterval = 120
    
    // MARK: - Initialization
    
    override init() {
        // Log the device name we're using
        let deviceName = UIDevice.current.name
        logger.debug("Initializing ConnectionManager with device name: \(deviceName, privacy: .public)")
        logger.debug("System info: \(UIDevice.current.systemName, privacy: .public) \(UIDevice.current.systemVersion, privacy: .public)")
        self.peerID = MCPeerID(displayName: deviceName)
        super.init()
        checkNetworkPermissions()
        setupMultipeerConnectivity()
    }
    
    private func checkNetworkPermissions() {
        logger.debug("Checking network permissions...")
        // Note: There's no direct API to check local network permission
        // but we can check for general network availability
        logger.debug("Network permission check complete")
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        logger.debug("Setting up Multipeer Connectivity with service type: \(self.serviceType, privacy: .public)")
        logger.debug("Peer ID: \(self.peerID.displayName, privacy: .public)")
        
        // Create session with required encryption for all peer-to-peer traffic
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session?.delegate = self
        
        // Create advertiser with discovery info to help with identification
        logger.debug("Creating advertiser for service: \(self.serviceType, privacy: .public)")
        let discoveryInfo = ["device": "AppleTV", "service": "eclipse-share"]
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser?.delegate = self
        logger.debug("Advertiser created successfully")
    }
    
    func startAdvertising() {
        guard !isAdvertising else { 
            logger.debug("Already advertising, skipping duplicate start")
            return 
        }
        
        logger.debug("Starting to advertise as: \(self.peerID.displayName, privacy: .public)")
        logger.debug("Service type: \(self.serviceType, privacy: .public)")
        
        // Check if advertiser exists
        if advertiser == nil {
            logger.error("Advertiser is nil! Recreating...")
            setupMultipeerConnectivity()
        }
        
        advertiser?.startAdvertisingPeer()
        isAdvertising = true
        logger.info("[Eclipse:CONN] AppleTV started advertising service '\(self.serviceType, privacy: .public)' as '\(self.peerID.displayName, privacy: .public)'")
        
        // Add a test to verify advertising is actually working
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyAdvertising()
        }
    }
    
    private func verifyAdvertising() {
        logger.debug("Verifying advertising status: isAdvertising=\(self.isAdvertising), advertiserExists=\(self.advertiser != nil)")
        if let advertiser = advertiser {
            logger.debug("Advertiser peer: \(advertiser.myPeerID.displayName, privacy: .public), service: \(advertiser.serviceType, privacy: .public)")
        }
    }
    
    func stopAdvertising() {
        guard isAdvertising else { return } // Prevent multiple stops
        
        logger.debug("Stopping advertising")
        advertiser?.stopAdvertisingPeer()
        isAdvertising = false
        logger.info("Stopped advertising")
    }
    
    func disconnect() {
        logger.debug("Disconnecting session")
        session?.disconnect()
        logger.info("Disconnected session")
        
        // Restart advertising after disconnection
        isAdvertising = false
        startAdvertising()
    }
    
    // Add method to check advertising status
    func isCurrentlyAdvertising() -> Bool {
        return isAdvertising
    }
    
    // Add method to force restart advertising
    func restartAdvertising() {
        logger.debug("Force restarting advertising")
        stopAdvertising()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.startAdvertising()
        }
    }

    // MARK: - Pairing

    /// Current 6-digit PIN shown on the TV for first-time pairing.
    var currentPairingPIN: String {
        pairedStore.currentPIN
    }

    /// Issues a new pairing PIN (e.g. after the user asks to re-pair).
    @discardableResult
    func rotatePairingPIN() -> String {
        pairedStore.rotatePIN()
    }

    /// Removes a previously paired iPhone from the allowlist.
    func forgetPairedPhone(named displayName: String) {
        pairedStore.forget(displayName: displayName)
    }

    /// Display names of phones that have successfully paired with this TV.
    var pairedPhoneNames: [String] {
        pairedStore.allPairedNames()
    }
    
    // MARK: - Move Mode Notifications
    
    /// Notify all connected peers that the app is in move mode
    func notifyMoveModeEnabled(_ enabled: Bool) {
        guard let session = session else { return }
        
        let message = enabled ? "MOVE_MODE_ENABLED" : "MOVE_MODE_DISABLED"
        
        if let data = message.data(using: .utf8) {
            do {
                try session.send(data, toPeers: session.connectedPeers, with: .reliable)
                logger.info("Sent move mode state (\(message)) to \(session.connectedPeers.count) peers")
            } catch {
                logger.error("Failed to send move mode state: \(error.localizedDescription)")
            }
        }
    }
    
    // MARK: - Library Mirroring (TV -> iPhone)

    /// Number of currently connected peers.
    var connectedPeerCount: Int {
        session?.connectedPeers.count ?? 0
    }

    /// Sends the full ordered library manifest (plus which item is live) to all peers.
    func sendLibraryManifest(items: [LibraryItemDTO], currentId: String?) {
        let mode = MediaDataSource.shared.activeLibraryMode
        sendControlMessage(
            .manifest(items: items, currentId: currentId).withLibraryMode(mode)
        )
    }

    /// Sends a lightweight update telling the companion which item is now live.
    func sendCurrentChanged(currentId: String?) {
        let mode = MediaDataSource.shared.activeLibraryMode
        sendControlMessage(.currentChanged(currentId: currentId).withLibraryMode(mode))
    }

    /// Reports the live video's playback state to the companion. Sent frequently while
    /// playing, so it travels unreliably to avoid head-of-line blocking behind transfers.
    func sendPlaybackStatus(currentId: String?, isPlaying: Bool, position: Double, duration: Double) {
        let mode = MediaDataSource.shared.activeLibraryMode
        guard let session = session, !session.connectedPeers.isEmpty,
              let data = EclipseShareEnvelope.playbackStatus(
                currentId: currentId, isPlaying: isPlaying,
                position: position, duration: duration
              ).withLibraryMode(mode).encoded() else {
            return
        }
        try? session.send(data, toPeers: session.connectedPeers, with: .unreliable)
    }

    /// Streams a thumbnail file to the first connected peer, keyed by item id.
    func sendThumbnail(at fileURL: URL, forId id: String) {
        guard let session = session, let peer = session.connectedPeers.first else { return }

        let resourceName = EclipseShareProtocol.thumbnailResourceName(for: id)
        session.sendResource(at: fileURL, withName: resourceName, toPeer: peer) { [weak self] error in
            // Best-effort: clean up the temporary thumbnail once the transfer settles.
            try? FileManager.default.removeItem(at: fileURL)
            if let error = error {
                self?.logger.error("Failed to send library thumbnail for \(id): \(error.localizedDescription)")
            }
        }
    }

    private func sendControlMessage(_ envelope: EclipseShareEnvelope) {
        guard let session = session,
              !session.connectedPeers.isEmpty,
              let data = envelope.encoded() else {
            return
        }

        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
        } catch {
            logger.error("Failed to send control message (\(envelope.eclipseMsg)): \(error.localizedDescription)")
        }
    }

    /// Ensures the active library matches the envelope's mode before applying a command.
    private func activateModeIfNeeded(from envelope: EclipseShareEnvelope) {
        let mode = envelope.resolvedLibraryMode
        if MediaDataSource.shared.activeLibraryMode != mode {
            MediaDataSource.shared.setActiveLibraryMode(mode)
        }
    }

    /// Routes a decoded control envelope received from a peer.
    private func handleControlEnvelope(_ envelope: EclipseShareEnvelope, from peerID: MCPeerID) {
        switch envelope.kind {
        case .setDisplayMode:
            let mode = envelope.resolvedLibraryMode
            logger.info("Received set_display_mode: \(mode.rawValue, privacy: .public)")
            DispatchQueue.main.async {
                MediaDataSource.shared.setActiveLibraryMode(mode)
            }
        case .setContentTransition:
            let style = envelope.contentTransition ?? "Cut"
            logger.info("Received set_content_transition: \(style, privacy: .public)")
            DispatchQueue.main.async {
                ContentTransitionSettings.apply(wireValue: style)
            }
        case .playRequest:
            guard let id = envelope.id else { return }
            logger.info("Received play request for id: \(id, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceivePlayRequestForId: id)
            }
        case .deleteItem:
            guard let id = envelope.id else { return }
            logger.info("Received delete request for id: \(id, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceiveDeleteRequestForId: id)
            }
        case .moveItem:
            guard let id = envelope.id, let toIndex = envelope.toIndex else { return }
            logger.info("Received move request for id: \(id, privacy: .public) -> \(toIndex)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceiveMoveRequestForId: id, toIndex: toIndex)
            }
        case .reorderItems:
            guard let orderedIds = envelope.orderedIds else { return }
            logger.info("Received reorder request for \(orderedIds.count) items")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceiveReorderRequest: orderedIds)
            }
        case .setVideoSetting:
            guard let id = envelope.id else { return }
            let isLooping = envelope.isLooping
            let isMuted = envelope.isMuted
            logger.info("Received video setting for id: \(id, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceiveVideoSettingForId: id,
                                                  isLooping: isLooping, isMuted: isMuted)
            }
        case .restoreItem:
            guard let id = envelope.id else { return }
            logger.info("Received restore request for id: \(id, privacy: .public)")
            // Activate mode so restore slot placement runs against the right ledger/UI.
            // File placement itself is stamped on the Multipeer resource name.
            DispatchQueue.main.async { [weak self] in
                self?.activateModeIfNeeded(from: envelope)
            }
            pendingRestore = (ledgerId: id, expires: Date().addingTimeInterval(restoreWindow))
        case .playbackCommand:
            guard let raw = envelope.playbackAction,
                  let action = EclipseShareProtocol.PlaybackAction(rawValue: raw) else { return }
            let position = envelope.position
            logger.info("Received playback command: \(raw, privacy: .public)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.activateModeIfNeeded(from: envelope)
                self.delegate?.connectionManager(self, didReceivePlaybackCommand: action, position: position)
            }
        case .setAccount:
            guard let code = envelope.accountCode, !code.isEmpty else { return }
            logger.info("Received set account code: \(code, privacy: .private)")
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.delegate?.connectionManager(self, didReceiveSetAccountCode: code)
            }
        case .libraryManifest, .currentChanged, .playbackStatus, .none:
            // These are TV -> iPhone only; ignore if a peer ever sends them back.
            break
        }
    }

    // MARK: - Resource Management
    
    /// Sanitizes a peer-supplied resource name into a safe, single path component.
    /// Strips any directory components and rejects names that attempt traversal,
    /// preventing a malicious peer from writing outside the media directory.
    private func sanitizedFileName(from resourceName: String) -> String? {
        // Collapse to just the last path component to drop any "../" or absolute prefixes
        let candidate = (resourceName as NSString).lastPathComponent
        guard !candidate.isEmpty,
              candidate != ".",
              candidate != "..",
              !candidate.contains("/"),
              !candidate.contains("\\") else {
            return nil
        }
        return candidate
    }

    private func handleConnectionError(_ error: Error, context: String) {
        if let mediaError = error as? MediaError {
            Task { @MainActor in
                ErrorHandler.shared.handle(mediaError, context: context)
            }
        } else {
            let mediaError = MediaError.connectionFailed(peerName: nil)
            Task { @MainActor in
                ErrorHandler.shared.handle(mediaError, context: context)
            }
        }
    }
    
    func cleanup() {
        logger.info("Cleaning up ConnectionManager resources")
        
        // Stop advertising
        stopAdvertising()
        
        // Disconnect session
        disconnect()
        
        // Reset state
        isAdvertising = false
        receivedImageCount = 0
        
        logger.info("ConnectionManager cleanup complete")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("[Eclipse:CONN] AppleTV received invitation from: \(peerID.displayName, privacy: .public)")
        
        // Check if we already have a connection
        if let session = session, !session.connectedPeers.isEmpty {
            logger.info("[Eclipse:CONN] AppleTV REJECTED invitation from \(peerID.displayName, privacy: .public): already connected to another peer")
            invitationHandler(false, nil)
            return
        }
        
        // Pairing: accept a correct on-screen PIN, or a remembered invite from an
        // already-paired phone. Reject missing/malformed/wrong-version contexts.
        guard let parsed = PeerPairing.parse(context) else {
            logger.error("[Eclipse:CONN] AppleTV REJECTED invitation from \(peerID.displayName, privacy: .private): missing or invalid pairing context")
            invitationHandler(false, nil)
            return
        }

        switch parsed {
        case .pin(let pin):
            guard pin == pairedStore.currentPIN else {
                logger.error("[Eclipse:CONN] AppleTV REJECTED invitation from \(peerID.displayName, privacy: .private): wrong PIN")
                invitationHandler(false, nil)
                return
            }
        case .remembered:
            guard pairedStore.isPaired(displayName: peerID.displayName) else {
                logger.error("[Eclipse:CONN] AppleTV REJECTED invitation from \(peerID.displayName, privacy: .private): not on allowlist")
                invitationHandler(false, nil)
                return
            }
        }

        logger.info("[Eclipse:CONN] AppleTV ACCEPTED invitation from \(peerID.displayName, privacy: .private)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logger.error("[Eclipse:CONN] AppleTV FAILED to start advertising: \(error.localizedDescription, privacy: .public)")
        
        // Set advertising flag to false
        isAdvertising = false
        
        // Handle specific error types
        if error.localizedDescription.contains("busy") || error.localizedDescription.contains("in use") {
            // Service type might be in use, wait longer before retrying
            logger.debug("Service appears busy, waiting 10 seconds before retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.startAdvertising()
            }
        } else {
            // General error, try sooner
            logger.debug("General error, retrying in 5 seconds")
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                self?.startAdvertising()
            }
        }
    }
}

// MARK: - MCSessionDelegate

extension ConnectionManager: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            logger.info("[Eclipse:CONN] AppleTV CONNECTED to: \(peerID.displayName, privacy: .private)")

            // First successful connect (PIN or remembered) lands the phone on the allowlist
            // so later reconnects can use the remembered context without re-entering a PIN.
            pairedStore.remember(displayName: peerID.displayName)
            // Rotate so a shoulder-surfed PIN cannot be reused by another device.
            pairedStore.rotatePIN()
            
            // Stop advertising once connected to avoid multiple connections
            stopAdvertising()
            
            // Always use main thread for delegate calls that might update UI
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didUpdateConnectionState: true, with: peerID)
            }
            // Push the full library so the companion can mirror it immediately.
            Task { @MainActor in
                self.librarySync?.peerDidConnect(peerID)
            }
            
        case .connecting:
            logger.info("[Eclipse:CONN] AppleTV connecting to: \(peerID.displayName, privacy: .public)")
            
        case .notConnected:
            logger.info("[Eclipse:CONN] AppleTV NOT connected to: \(peerID.displayName, privacy: .public)")
            
            // Restart advertising if we get disconnected
            if !isAdvertising {
                startAdvertising()
            }
            
            // Always use main thread for delegate calls that might update UI
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didUpdateConnectionState: false, with: peerID)
            }
            Task { @MainActor in
                self.librarySync?.peerDidDisconnect(peerID)
            }
            
        @unknown default:
            logger.warning("Unknown connection state: \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        logger.debug("Received data from \(peerID.displayName, privacy: .private): \(data.count) bytes")

        // Control envelopes only. Media arrives via sendResource; the legacy
        // in-memory video/image data path has been removed.
        if let envelope = EclipseShareEnvelope.decode(from: data) {
            handleControlEnvelope(envelope, from: peerID)
            return
        }

        // Plain-string move-mode signals from older paths / acknowledgements.
        if let message = String(data: data, encoding: .utf8) {
            if message == "MOVE_MODE_ENABLED" || message == "MOVE_MODE_DISABLED" {
                return
            }
        }

        logger.debug("Ignoring non-envelope data (\(data.count) bytes) from \(peerID.displayName, privacy: .private)")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for our simple image sharing
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.info("Started receiving resource: \(resourceName) from: \(peerID.displayName, privacy: .private)")
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            logger.error("Error receiving resource: \(error.localizedDescription)")
            Task { @MainActor in
                ErrorHandler.shared.handle(.transferCorrupted(fileName: resourceName, expectedSize: 0, actualSize: 0), context: "ConnectionManager.didFinishReceivingResource")
            }
            return
        }
        guard let localURL = localURL else {
            logger.error("Resource URL is nil")
            Task { @MainActor in
                ErrorHandler.shared.handle(.fileNotFound(path: resourceName), context: "ConnectionManager.didFinishReceivingResource")
            }
            return
        }
        logger.info("Received resource: \(resourceName, privacy: .public)")
        
        // Reject any resource whose name attempts directory traversal
        guard let safeName = sanitizedFileName(from: resourceName) else {
            logger.error("Rejected resource with unsafe name: \(resourceName, privacy: .public)")
            try? FileManager.default.removeItem(at: localURL)
            return
        }

        // Mode is stamped in the wire name (`eclmode_<mode>_<file>`). Fall back to the
        // active library for legacy unprefixed peers.
        let parsed = EclipseShareProtocol.parseMediaResourceName(safeName)
        let fileName = parsed.fileName
        let libraryMode = parsed.mode ?? MediaDataSource.shared.activeLibraryMode

        // Check if this is a custom thumbnail
        if fileName.hasPrefix("thumbnail_") {
            let videoFileName = String(fileName.dropFirst(10))
            if !videoFileName.isEmpty,
               ReceivedMediaValidator.isValidImage(at: localURL),
               let thumbnailImage = UIImage(contentsOfFile: localURL.path) {
                let videoPath = ImageStorage.shared
                    .getImagesDirectory(for: libraryMode)
                    .appendingPathComponent(videoFileName).path
                VideoThumbnailCache.shared.cacheThumbnail(thumbnailImage, for: videoPath)
                logger.info("Cached custom thumbnail for video: \(videoFileName, privacy: .public)")
            }
            try? FileManager.default.removeItem(at: localURL)
            return
        }

        guard let kind = ReceivedMediaValidator.kind(forExtension: (fileName as NSString).pathExtension) else {
            logger.error("Rejected resource with unsupported extension: \(fileName, privacy: .public)")
            try? FileManager.default.removeItem(at: localURL)
            return
        }

        // Validate content before committing into Caches/Media.
        let isValid: Bool
        switch kind {
        case .image: isValid = ReceivedMediaValidator.isValidImage(at: localURL)
        case .video: isValid = ReceivedMediaValidator.isValidVideo(at: localURL)
        }
        guard isValid else {
            try? FileManager.default.removeItem(at: localURL)
            if let errorData = (kind == .video ? "VIDEO_ERROR" : "IMAGE_ERROR").data(using: .utf8) {
                try? session.send(errorData, toPeers: [peerID], with: .reliable)
            }
            return
        }

        let fileManager = FileManager.default
        _ = ImageStorage.shared.createImagesDirectory(for: libraryMode)
        let destinationURL = ImageStorage.shared
            .getImagesDirectory(for: libraryMode)
            .appendingPathComponent(fileName)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: localURL, to: destinationURL)

            let isVideo = (kind == .video)
            let confirmationMessage = isVideo ? "VIDEO_RECEIVED" : "IMAGE_RECEIVED"
            if let confirmation = confirmationMessage.data(using: .utf8) {
                try? session.send(confirmation, toPeers: [peerID], with: .reliable)
            }

            var restoreLedgerId: String?
            if let pending = pendingRestore {
                pendingRestore = nil
                if Date() < pending.expires {
                    restoreLedgerId = pending.ledgerId
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if isVideo {
                    self.delegate?.connectionManager(self, didReceiveVideoAt: destinationURL.path)
                } else {
                    self.delegate?.connectionManager(self, didReceiveImageAt: destinationURL.path)
                }
                if let ledgerId = restoreLedgerId {
                    self.delegate?.connectionManager(self, didRestoreItemForLedgerId: ledgerId,
                                                     newPath: destinationURL.path)
                }
            }
        } catch {
            logger.error("Failed to move received resource: \(error.localizedDescription)")
            try? FileManager.default.removeItem(at: localURL)
            Task { @MainActor in
                ErrorHandler.shared.handle(.permissionDenied(operation: "moving received file"), context: "ConnectionManager.didFinishReceivingResource")
            }
        }
    }
}
