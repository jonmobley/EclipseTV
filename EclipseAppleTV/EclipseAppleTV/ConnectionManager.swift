import UIKit
import MultipeerConnectivity
import os.log

protocol ConnectionManagerDelegate: AnyObject {
    func connectionManager(_ manager: ConnectionManager, didReceiveImageAt path: String)
    func connectionManager(_ manager: ConnectionManager, didReceiveVideoAt path: String)
    func connectionManager(_ manager: ConnectionManager, didUpdateConnectionState connected: Bool, with peer: MCPeerID?)
}

class ConnectionManager: NSObject {
    // MARK: - Properties
    
    private let serviceType = "eclipse-share" // MUST MATCH EXACTLY on both devices

    /// Shared handshake token used to authenticate peers. MUST MATCH the value in
    /// the iPhone companion app's `iPhoneConnectionManager`.
    private let handshakeToken = "EclipseShare/v1"

    /// Hard ceiling for an in-memory video transfer (legacy chunked path) to avoid
    /// a malicious or buggy peer exhausting memory.
    private let maxInMemoryVideoBytes: Int64 = 2_000_000_000 // 2 GB

    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private let peerID: MCPeerID
    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "ConnectionManager")
    
    weak var delegate: ConnectionManagerDelegate?
    private var receivedImageCount = 0
    private var isAdvertising = false
    
    // Add properties for video transfer
    private var videoBuffer: Data?
    private var expectedVideoSize: Int64?
    
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
        logger.info("Started advertising as: \(self.peerID.displayName)")
        
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
        
        // Clear buffers
        videoBuffer = nil
        expectedVideoSize = nil
        
        // Reset state
        isAdvertising = false
        receivedImageCount = 0
        
        logger.info("ConnectionManager cleanup complete")
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension ConnectionManager: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID, withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        logger.info("Received invitation from: \(peerID.displayName)")
        
        // Check if we already have a connection
        if let session = session, !session.connectedPeers.isEmpty {
            logger.info("Already connected to another peer, rejecting invitation")
            invitationHandler(false, nil)
            return
        }
        
        // Require a matching handshake token. Reject any peer that does not present
        // the shared secret, including peers that send no context at all.
        guard let contextData = context,
              let contextString = String(data: contextData, encoding: .utf8) else {
            logger.error("Rejected invitation from \(peerID.displayName): missing context")
            invitationHandler(false, nil)
            return
        }

        guard contextString.contains(handshakeToken) else {
            logger.error("Rejected invitation from \(peerID.displayName): invalid token")
            invitationHandler(false, nil)
            return
        }

        logger.info("Accepted invitation from \(peerID.displayName)")
        invitationHandler(true, session)
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        logger.error("Failed to start advertising: \(error.localizedDescription)")
        
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
            logger.info("Connected to: \(peerID.displayName)")
            
            // Stop advertising once connected to avoid multiple connections
            stopAdvertising()
            
            // Always use main thread for delegate calls that might update UI
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didUpdateConnectionState: true, with: peerID)
            }
            
        case .connecting:
            logger.info("Connecting to: \(peerID.displayName)")
            
        case .notConnected:
            logger.info("Disconnected from: \(peerID.displayName)")
            
            // Restart advertising if we get disconnected
            if !isAdvertising {
                startAdvertising()
            }
            
            // Always use main thread for delegate calls that might update UI
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didUpdateConnectionState: false, with: peerID)
            }
            
        @unknown default:
            logger.warning("Unknown connection state: \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        logger.debug("Received data from \(peerID.displayName): \(data.count) bytes")
        
        // Check if this is a video metadata message
        if let message = String(data: data, encoding: .utf8),
           let jsonData = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
           json["type"] == "video",
           let sizeString = json["size"],
           let videoSize = Int64(sizeString) {
            
            // Reject absurd / hostile sizes before allocating any buffer
            guard videoSize > 0, videoSize <= maxInMemoryVideoBytes else {
                logger.error("Rejected video transfer: declared size \(videoSize) bytes out of bounds")
                videoBuffer = nil
                expectedVideoSize = nil
                return
            }

            logger.debug("Starting video transfer of size: \(videoSize) bytes")
            // Initialize video buffer
            videoBuffer = Data()
            expectedVideoSize = videoSize
            return
        }
        
        // Check if this is a video completion message
        if let message = String(data: data, encoding: .utf8),
           message == "VIDEO_COMPLETE" {
            // Video transfer complete, save the video
            if let videoData = videoBuffer {
                logger.debug("Video transfer complete, saving \(videoData.count) bytes")
                if let videoURL = ImageStorage.shared.saveReceivedVideo(videoData) {
                    logger.info("Video saved successfully at: \(videoURL.path, privacy: .public)")
                    
                    // Send confirmation back to iPhone
                    let confirmation = "VIDEO_RECEIVED".data(using: .utf8)!
                    do {
                        try session.send(confirmation, toPeers: [peerID], with: .reliable)
                        logger.debug("Sent video confirmation to iPhone")
                        
                        // Notify delegate on main thread
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.connectionManager(self, didReceiveVideoAt: videoURL.path)
                        }
                    } catch {
                        logger.error("Failed to send video confirmation: \(error.localizedDescription)")
                    }
                } else {
                    logger.error("Failed to save video")
                    Task { @MainActor in
                        ErrorHandler.shared.handle(.fileCorrupted(path: "received_video", reason: "Could not save video data"), context: "ConnectionManager.didReceive")
                    }
                    
                    // Send error back to iPhone
                    let error = "VIDEO_ERROR".data(using: .utf8)!
                    do {
                        try session.send(error, toPeers: [peerID], with: .reliable)
                    } catch {
                        handleConnectionError(error, context: "sending video error response")
                    }
                }
            }
            // Reset video transfer state
            videoBuffer = nil
            expectedVideoSize = nil
            return
        }
        
        // Handle video chunks
        if let expectedSize = expectedVideoSize, var buffer = videoBuffer {
            // Guard against receiving more data than declared (and against the hard cap)
            let projectedSize = Int64(buffer.count) + Int64(data.count)
            guard projectedSize <= expectedSize, projectedSize <= maxInMemoryVideoBytes else {
                logger.error("Aborted video transfer: projected \(projectedSize) bytes exceeds expected \(expectedSize)")
                videoBuffer = nil
                expectedVideoSize = nil
                return
            }

            buffer.append(data)
            videoBuffer = buffer
            
            // Log progress
            if let currentSize = videoBuffer?.count {
                let progress = Double(currentSize) / Double(expectedSize) * 100
                logger.debug("Video transfer progress: \(Int(progress))%")
            }
            return
        }
        
        // Handle image data
        if let imageURL = ImageStorage.shared.saveReceivedImage(data) {
            logger.info("Image saved successfully at: \(imageURL.path, privacy: .public)")
            
            // Send confirmation back to iPhone
            let confirmation = "IMAGE_RECEIVED".data(using: .utf8)!
            do {
                try session.send(confirmation, toPeers: [peerID], with: .reliable)
                logger.debug("Sent image confirmation to iPhone")
                
                // Notify delegate on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.connectionManager(self, didReceiveImageAt: imageURL.path)
                }
            } catch {
                logger.error("Failed to send image confirmation: \(error.localizedDescription)")
            }
        } else {
            logger.error("Failed to save image")
            Task { @MainActor in
                ErrorHandler.shared.handle(.fileCorrupted(path: "received_image", reason: "Could not save received data"), context: "ConnectionManager.didReceive")
            }
            
            let error = "IMAGE_ERROR".data(using: .utf8)!
            do {
                try session.send(error, toPeers: [peerID], with: .reliable)
            } catch {
                handleConnectionError(error, context: "sending error response")
            }
        }
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used for our simple image sharing
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        logger.info("Started receiving resource: \(resourceName) from: \(peerID.displayName)")
        // Optionally, observe progress here if you want to show a progress bar
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
        logger.info("Received resource: \(resourceName) at: \(localURL.path)")
        
        // Reject any resource whose name attempts directory traversal
        guard let safeName = sanitizedFileName(from: resourceName) else {
            logger.error("Rejected resource with unsafe name: \(resourceName)")
            try? FileManager.default.removeItem(at: localURL)
            return
        }
        
        // Check if this is a custom thumbnail
        if safeName.hasPrefix("thumbnail_") {
            // This is a custom thumbnail for a video
            let videoFileName = String(safeName.dropFirst(10)) // Remove "thumbnail_" prefix
            
            // Load the thumbnail image and cache it
            if !videoFileName.isEmpty, let thumbnailImage = UIImage(contentsOfFile: localURL.path) {
                let videoPath = ImageStorage.shared.getImagesDirectory().appendingPathComponent(videoFileName).path
                VideoThumbnailCache.shared.cacheThumbnail(thumbnailImage, for: videoPath)
                logger.info("Cached custom thumbnail for video: \(videoFileName)")
            }
            
            // Clean up the temporary thumbnail file
            try? FileManager.default.removeItem(at: localURL)
            return
        }
        
        // Move the received file to our storage as a video or image
        let fileManager = FileManager.default
        let destinationURL = ImageStorage.shared.getImagesDirectory().appendingPathComponent(safeName)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: localURL, to: destinationURL)

            let ext = destinationURL.pathExtension.lowercased()
            let videoExtensions: Set<String> = ["mp4", "mov", "m4v"]
            let imageExtensions: Set<String> = ["jpg", "jpeg", "png", "heic"]
            let isVideo = videoExtensions.contains(ext)
            let isImage = imageExtensions.contains(ext)

            // Send a confirmation back to the sender so it can report success symmetrically
            // with the legacy in-memory transfer path.
            if isVideo || isImage {
                let confirmationMessage = isVideo ? "VIDEO_RECEIVED" : "IMAGE_RECEIVED"
                if let confirmation = confirmationMessage.data(using: .utf8) {
                    try? session.send(confirmation, toPeers: [peerID], with: .reliable)
                }
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                if isVideo {
                    self.delegate?.connectionManager(self, didReceiveVideoAt: destinationURL.path)
                } else if isImage {
                    self.delegate?.connectionManager(self, didReceiveImageAt: destinationURL.path)
                }
            }
        } catch {
            logger.error("Failed to move received resource: \(error.localizedDescription)")
            Task { @MainActor in
                ErrorHandler.shared.handle(.permissionDenied(operation: "moving received file"), context: "ConnectionManager.didFinishReceivingResource")
            }
        }
    }
}
