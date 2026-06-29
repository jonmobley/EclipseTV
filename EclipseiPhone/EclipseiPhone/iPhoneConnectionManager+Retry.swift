// iPhoneConnectionManager+Retry.swift
import Foundation
import MultipeerConnectivity

// MARK: - Connection Retry Logic

/// Exponential-backoff reconnection to the active Apple TV after an unexpected drop.
/// Replica TVs are not retried here; they are re-invited on rediscovery.
extension iPhoneConnectionManager {
    func scheduleReconnectAttempt(to peer: MCPeerID) {
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
    
    func resetRetryCount() {
        retryCount = 0
        retryTimer?.invalidate()
        retryTimer = nil
    }
}
