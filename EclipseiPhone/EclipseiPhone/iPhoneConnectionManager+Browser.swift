//
//  iPhoneConnectionManager+Browser.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneConnectionManager+Browser.swift
import MultipeerConnectivity

// MARK: - MCNearbyServiceBrowserDelegate

/// Peer discovery: tracks Apple TVs as they appear/disappear and, while "keep all in
/// sync" is on, auto-invites each newly discovered TV as a replica.
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
