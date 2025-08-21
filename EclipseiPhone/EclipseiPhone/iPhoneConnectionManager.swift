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
}

class iPhoneConnectionManager: NSObject {
    // MARK: - Properties
    
    private let serviceType = "eclipse-share" // MUST MATCH EXACTLY on both devices
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
        print("📱 Initializing iPhoneConnectionManager with device name: \(deviceName)")
        self.peerID = MCPeerID(displayName: deviceName)
        super.init()
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
        print("📱 App became active, ensuring connection")
        // If we have a peer but aren't connected, try to reconnect
        if let selectedPeer = discoveredPeers.first, session?.connectedPeers.isEmpty == true {
            print("🔄 Trying to reconnect to \(selectedPeer.displayName)")
            invitePeer(selectedPeer)
        } else if discoveredPeers.isEmpty && !isBrowsing {
            // If we don't have any discovered peers, start browsing
            startBrowsing()
        }
    }
    
    // MARK: - Multipeer Connectivity
    
    private func setupMultipeerConnectivity() {
        print("🔄 Setting up Multipeer Connectivity with service type: \(serviceType)")
        print("🔧 Peer ID: \(peerID.displayName)")
        
        // Create session with optimized settings for better reliability
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .optional)
        session?.delegate = self
        
        // Create browser
        print("🔍 Creating browser for service: \(serviceType)")
        browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
        browser?.delegate = self
        print("✅ Browser created successfully")
    }
    
    // MARK: - Public Methods
    
    func isConnectedToPeer(_ peer: MCPeerID) -> Bool {
        return session?.connectedPeers.contains(peer) == true
    }
    
    func startBrowsing() {
        print("🔍 Starting browsing for peers")
        print("🔧 iOS Version: \(UIDevice.current.systemVersion)")
        print("🔧 Device Model: \(UIDevice.current.model)")
        
        // Check if browser exists
        if browser == nil {
            print("❌ Browser is nil! Recreating...")
            setupMultipeerConnectivity()
        }
        
        discoveredPeers.removeAll()
        browser?.startBrowsingForPeers()
        isBrowsing = true
        logger.info("Started browsing for peers")
        
        // Add verification after a delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.verifyBrowsing()
        }
    }
    
    private func verifyBrowsing() {
        print("🔍 Verifying browsing status after 2 seconds...")
        print("🔍 isBrowsing flag: \(isBrowsing)")
        print("🔍 Browser exists: \(browser != nil)")
        print("🔍 Discovered peers count: \(discoveredPeers.count)")
        if let browser = browser {
            print("🔍 Browser peer: \(browser.myPeerID.displayName)")
            print("🔍 Browser service type: \(browser.serviceType)")
        }
        for (index, peer) in discoveredPeers.enumerated() {
            print("🔍 Peer \(index): \(peer.displayName)")
        }
    }
    
    func stopBrowsing() {
        print("🛑 Stopping browsing")
        browser?.stopBrowsingForPeers()
        isBrowsing = false
        logger.info("Stopped browsing for peers")
    }
    
    func invitePeer(_ peer: MCPeerID) {
        guard let session = session else {
            print("❌ Cannot invite peer: session is nil")
            return
        }
        
        // Don't invite if we're already connected to this peer
        if session.connectedPeers.contains(peer) {
            print("✅ Already connected to peer: \(peer.displayName)")
            return
        }
        
        // Don't invite if we're currently connecting to this peer
        if session.connectedPeers.isEmpty == false {
            print("🔄 Already connecting/connected to another peer")
            return
        }
        
        print("📨 Inviting peer: \(peer.displayName)")
        // Increase timeout to 60 seconds and provide discovery info
        let context = "iPhone-Connection".data(using: .utf8)
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 60)
        logger.info("Invited peer: \(peer.displayName)")
    }
    
    func disconnect() {
        print("🔌 Disconnecting session")
        session?.disconnect()
        logger.info("Disconnected session")
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

        let fileName = imageURL.lastPathComponent
        let progress = session.sendResource(at: imageURL, withName: fileName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Always clean up observer when transfer completes
                self.cleanupCurrentProgress()
                
                if let error = error {
                    self.logger.error("Image transfer failed: \(error.localizedDescription)")
                    self.delegate?.connectionManager(self, didUpdateImageTransferProgress: 0)
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
            
            // Send custom thumbnail first
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
            }
        }

        let progress = session.sendResource(at: videoURL, withName: fileName, toPeer: peer) { [weak self] error in
            DispatchQueue.main.async {
                guard let self = self else { return }
                
                // Always clean up observer when transfer completes
                self.cleanupCurrentProgress()
                self.isTransferringVideo = false
                
                if let error = error {
                    self.logger.error("Video transfer failed: \(error.localizedDescription)")
                    self.delegate?.connectionManager(self, didUpdateVideoTransferProgress: 0)
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
        
        return true
    }
    
    // MARK: - Connection Retry Logic
    
    private func scheduleReconnectAttempt(to peer: MCPeerID) {
        // Cancel any existing retry timer
        retryTimer?.invalidate()
        
        guard retryCount < maxRetries else {
            print("❌ Max retry attempts reached for peer: \(peer.displayName)")
            retryCount = 0
            return
        }
        
        retryCount += 1
        let delay = TimeInterval(retryCount * 2) // Exponential backoff: 2s, 4s, 6s
        
        print("⏱️ Scheduling reconnect attempt \(retryCount)/\(maxRetries) in \(delay)s")
        
        retryTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            print("🔄 Retry attempt \(self.retryCount) to reconnect to \(peer.displayName)")
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
        print("🔍 Found peer: \(peerID.displayName)")
        if let info = info {
            print("🔍 Discovery info: \(info)")
        } else {
            print("🔍 No discovery info provided")
        }
        logger.info("Found peer: \(peerID.displayName)")
        
        // Track discovered peer
        if !discoveredPeers.contains(peerID) {
            discoveredPeers.append(peerID)
        }
        
        DispatchQueue.main.async {
            self.delegate?.connectionManager(self, didFindPeer: peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        print("❌ Lost peer: \(peerID.displayName)")
        logger.info("Lost peer: \(peerID.displayName)")
        
        if let index = discoveredPeers.firstIndex(of: peerID) {
            discoveredPeers.remove(at: index)
        }
        
        DispatchQueue.main.async {
            self.delegate?.connectionManager(self, didLosePeer: peerID)
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        print("❌ Failed to start browsing: \(error.localizedDescription)")
        logger.error("Failed to start browsing: \(error.localizedDescription)")
        
        // Handle specific error types and retry
        if error.localizedDescription.contains("busy") || error.localizedDescription.contains("in use") {
            print("🔄 Browser service appears busy, waiting 10 seconds before retry")
            DispatchQueue.main.asyncAfter(deadline: .now() + 10.0) { [weak self] in
                if let self = self, !self.isBrowsing {
                    self.startBrowsing()
                }
            }
        } else {
            print("🔄 General browser error, retrying in 5 seconds")
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
        print("🔄 Peer \(peerID.displayName) changed state to: \(state.rawValue)")
        
        switch state {
        case .connected:
            logger.info("Connected to peer: \(peerID.displayName)")
            // Stop browsing once connected to avoid duplicate connections
            stopBrowsing()
            // Reset retry count on successful connection
            resetRetryCount()
            DispatchQueue.main.async {
                self.delegate?.connectionManager(self, didConnectToPeer: peerID)
            }
            
        case .connecting:
            logger.info("Connecting to peer: \(peerID.displayName)")
            
        case .notConnected:
            logger.info("Disconnected from peer: \(peerID.displayName)")
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
            print("❓ Unknown session state: \(state.rawValue)")
            logger.error("Unknown session state: \(state.rawValue)")
        }
    }
    
    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        // Check if this is a confirmation message
        if let message = String(data: data, encoding: .utf8) {
            if message == "IMAGE_RECEIVED" {
                print("📱 Received confirmation from Apple TV")
                // Notify delegate that image was received by Apple TV
                delegate?.connectionManager(self, didReceiveConfirmationFromPeer: peerID)
                return
            }
            
            // Handle move mode status messages
            if message == "MOVE_MODE_ENABLED" {
                print("📱 Apple TV entered move mode")
                isAppleTVInMoveMode = true
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveMoveModeState: true)
                }
                return
            }
            
            if message == "MOVE_MODE_DISABLED" {
                print("📱 Apple TV exited move mode")
                isAppleTVInMoveMode = false
                DispatchQueue.main.async {
                    self.delegate?.connectionManager(self, didReceiveMoveModeState: false)
                }
                return
            }
        }
        
        // Handle other data types if needed
        print("📱 Received data from peer: \(peerID.displayName)")
    }
    
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {
        // Not used in this app
    }
    
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {
        // Not used in this app
    }
    
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {
        // Not used in this app
    }
}
