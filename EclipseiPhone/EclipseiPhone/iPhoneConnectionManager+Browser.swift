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

        // Browser callbacks arrive on a background queue. Hop to main so all reads/writes
        // of connection state (`discoveredPeers`, invitations) happen on one thread.
        DispatchQueue.main.async {
            if !self.discoveredPeers.contains(peerID) {
                self.discoveredPeers.append(peerID)
            }

            self.delegate?.connectionManager(self, didFindPeer: peerID)

            // When keeping all Apple TVs in sync, connect every newly discovered TV (the
            // first to connect becomes the active/mirrored TV; the rest are sync replicas).
            if self.syncAllEnabled, self.session?.connectedPeers.contains(peerID) != true {
                self.invitePeer(peerID)
            }
        }
    }
    
    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        logger.info("[Eclipse:CONN] iPhone lost peer: \(peerID.displayName, privacy: .public)")

        DispatchQueue.main.async {
            if let index = self.discoveredPeers.firstIndex(of: peerID) {
                self.discoveredPeers.remove(at: index)
            }

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
