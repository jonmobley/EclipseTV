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
        print("📱 Initializing ConnectionManager with device name: \(deviceName)")
        print("📱 System info: \(UIDevice.current.systemName) \(UIDevice.current.systemVersion)")
        self.peerID = MCPeerID(displayName: deviceName)
        super.init()
        checkNetworkPermissions()
        setupMultipeerConnectivity()
    }
    
    private func checkNetworkPermissions() {
        print("🔐 Checking network permissions...")
        // Note: There's no direct API to check local network permission
        // but we can check for general network availability
        print("🔐 Network permission check complete")
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        print("🔄 Setting up Multipeer Connectivity with service type: \(serviceType)")
        print("🔧 Peer ID: \(peerID.displayName)")
        
        // Create session with optimized settings for better reliability
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .optional)
        session?.delegate = self
        
        // Create advertiser with discovery info to help with identification
        print("📢 Creating advertiser for service: \(serviceType)")
        let discoveryInfo = ["device": "AppleTV", "service": "eclipse-share"]
        advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: discoveryInfo, serviceType: serviceType)
        advertiser?.delegate = self
        print("✅ Advertiser created successfully")
    }
    
    func startAdvertising() {
        guard !isAdvertising else { 
            print("⚠️ Already advertising, skipping duplicate start")
            return 
        }
        
        print("📣 Starting to advertise as: \(self.peerID.displayName)")
        print("🔧 Service type: \(serviceType)")
        print("🔧 iOS Version: \(UIDevice.current.systemVersion)")
        print("🔧 Device Model: \(UIDevice.current.model)")
        
        // Check if advertiser exists
        if advertiser == nil {
            print("❌ Advertiser is nil! Recreating...")
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
        print("🔍 Verifying advertising status after 2 seconds...")
        print("🔍 isAdvertising flag: \(isAdvertising)")
        print("🔍 Advertiser exists: \(advertiser != nil)")
        if let advertiser = advertiser {
            print("🔍 Advertiser peer: \(advertiser.myPeerID.displayName)")
            print("🔍 Advertiser service type: \(advertiser.serviceType)")
        }
    }
    
    func stopAdvertising() {
        guard isAdvertising else { return } // Prevent multiple stops
        
        print("🛑 Stopping advertising")
        advertiser?.stopAdvertisingPeer()
        isAdvertising = false
        logger.info("Stopped advertising")
    }
    
    func disconnect() {
        print("🔌 Disconnecting session")
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
        print("🔄 Force restarting advertising")
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
        print("📩 Received invitation from: \(peerID.displayName)")
        logger.info("Received invitation from: \(peerID.displayName)")
        
        // Check if we already have a connection
        if let session = session, !session.connectedPeers.isEmpty {
            print("❌ Already connected to another peer, rejecting invitation")
            invitationHandler(false, nil)
            return
        }
        
        // Verify the context if provided
        if let contextData = context,
           let contextString = String(data: contextData, encoding: .utf8) {
            print("📝 Invitation context: \(contextString)")
            
            // Only accept invitations from iPhone clients
            if contextString.contains("iPhone") {
                print("✅ Accepting invitation from iPhone client")
                invitationHandler(true, session)
            } else {
                print("❌ Rejecting invitation from unknown client")
                invitationHandler(false, nil)
            }
        } else {
            // Accept invitation even without context for backward compatibility
            print("✅ Accepting invitation (no context provided)")
            invitationHandler(true, session)
        }
    }
    
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        print("❌ Failed to start advertising: \(error.localizedDescription)")
        print("❌ Error details: \(error)")
        print("❌ Service type: \(serviceType)")
        logger.error("Failed to start advertising: \(error.localizedDescription)")
        
        // Set advertising flag to false
        isAdvertising = false
        
        // Handle specific error types
        if error.localizedDescription.contains("busy") || error.localizedDescription.contains("in use") {
            // Service type might be in use, wait longer before retrying
            print("🔄 Service appears busy, waiting 10 seconds before retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                self?.startAdvertising()
            }
        } else {
            // General error, try sooner
            print("🔄 General error, retrying in 5 seconds")
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
            print("🔗 Connected to: \(peerID.displayName)")
            logger.info("Connected to: \(peerID.displayName)")
            
            // Stop advertising once connected to avoid multiple connections
            stopAdvertising()
            
            // Always use main thread for delegate calls that might update UI
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didUpdateConnectionState: true, with: peerID)
            }
            
        case .connecting:
            print("🔄 Connecting to: \(peerID.displayName)")
            logger.info("Connecting to: \(peerID.displayName)")
            
        case .notConnected:
            print("❌ Disconnected from: \(peerID.displayName)")
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
            print("❓ Unknown connection state: \(peerID.displayName)")
            logger.warning("Unknown connection state: \(peerID.displayName)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        print("📥 Received data from \(peerID.displayName): \(data.count) bytes")
        
        // Check if this is a video metadata message
        if let message = String(data: data, encoding: .utf8),
           let jsonData = message.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: String],
           json["type"] == "video",
           let sizeString = json["size"],
           let videoSize = Int64(sizeString) {
            
            print("📥 Starting video transfer of size: \(videoSize) bytes")
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
                print("📥 Video transfer complete, saving \(videoData.count) bytes")
                if let videoURL = ImageStorage.shared.saveReceivedVideo(videoData) {
                    print("✅ Video saved successfully at: \(videoURL.path)")
                    
                    // Send confirmation back to iPhone
                    let confirmation = "VIDEO_RECEIVED".data(using: .utf8)!
                    do {
                        try session.send(confirmation, toPeers: [peerID], with: .reliable)
                        print("✅ Sent video confirmation to iPhone")
                        
                        // Notify delegate on main thread
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            self.delegate?.connectionManager(self, didReceiveVideoAt: videoURL.path)
                        }
                    } catch {
                        print("❌ Failed to send video confirmation: \(error)")
                    }
                } else {
                    print("❌ Failed to save video")
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
            buffer.append(data)
            videoBuffer = buffer
            
            // Log progress
            if let currentSize = videoBuffer?.count {
                let progress = Double(currentSize) / Double(expectedSize) * 100
                print("📥 Video transfer progress: \(Int(progress))%")
            }
            return
        }
        
        // Handle image data
        if let imageURL = ImageStorage.shared.saveReceivedImage(data) {
            print("✅ Image saved successfully at: \(imageURL.path)")
            
            // Send confirmation back to iPhone
            let confirmation = "IMAGE_RECEIVED".data(using: .utf8)!
            do {
                try session.send(confirmation, toPeers: [peerID], with: .reliable)
                print("✅ Sent image confirmation to iPhone")
                
                // Notify delegate on main thread
                DispatchQueue.main.async { [weak self] in
                    guard let self = self else { return }
                    self.delegate?.connectionManager(self, didReceiveImageAt: imageURL.path)
                }
            } catch {
                print("❌ Failed to send image confirmation: \(error)")
            }
        } else {
            print("❌ Failed to save image")
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
        print("⬇️ Started receiving resource: \(resourceName) from: \(peerID.displayName)")
        logger.info("Started receiving resource: \(resourceName) from: \(peerID.displayName)")
        // Optionally, observe progress here if you want to show a progress bar
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        if let error = error {
            print("❌ Error receiving resource: \(error.localizedDescription)")
            Task { @MainActor in
                ErrorHandler.shared.handle(.transferCorrupted(fileName: resourceName, expectedSize: 0, actualSize: 0), context: "ConnectionManager.didFinishReceivingResource")
            }
            return
        }
        guard let localURL = localURL else {
            print("❌ Resource URL is nil")
            Task { @MainActor in
                ErrorHandler.shared.handle(.fileNotFound(path: resourceName), context: "ConnectionManager.didFinishReceivingResource")
            }
            return
        }
        print("✅ Received resource: \(resourceName) at: \(localURL.path)")
        logger.info("Received resource: \(resourceName) at: \(localURL.path)")
        
        // Check if this is a custom thumbnail
        if resourceName.hasPrefix("thumbnail_") {
            // This is a custom thumbnail for a video
            let videoFileName = String(resourceName.dropFirst(10)) // Remove "thumbnail_" prefix
            
            // Load the thumbnail image and cache it
            if let thumbnailImage = UIImage(contentsOfFile: localURL.path) {
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
        let destinationURL = ImageStorage.shared.getImagesDirectory().appendingPathComponent(resourceName)
        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.moveItem(at: localURL, to: destinationURL)
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                let ext = destinationURL.pathExtension.lowercased()
                if ext == "mp4" || ext == "mov" {
                    self.delegate?.connectionManager(self, didReceiveVideoAt: destinationURL.path)
                } else if ext == "jpg" || ext == "jpeg" || ext == "png" {
                    self.delegate?.connectionManager(self, didReceiveImageAt: destinationURL.path)
                }
            }
        } catch {
            print("❌ Failed to move received resource: \(error)")
            Task { @MainActor in
                ErrorHandler.shared.handle(.permissionDenied(operation: "moving received file"), context: "ConnectionManager.didFinishReceivingResource")
            }
        }
    }
}
