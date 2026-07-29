// iPhoneConnectionManager+Retry.swift
import Foundation
import MultipeerConnectivity

// MARK: - Connection Retry Logic

/// Exponential-backoff reconnection to the active Apple TV after an unexpected drop.
/// Replica TVs are not retried here; they are re-invited on rediscovery.
extension iPhoneConnectionManager {

    /// Ceiling for the reconnect delay, so a raised `maxRetries` can never push the last
    /// attempt minutes out.
    private static let maxReconnectDelay: TimeInterval = 30

    func scheduleReconnectAttempt(to peer: MCPeerID) {
        // `Timer.scheduledTimer` attaches to the *current* run loop. If this runs on a
        // background queue (e.g. an MCSession delegate callback) that run loop isn't
        // spinning and the timer never fires. Always schedule on the main run loop so the
        // exponential-backoff reconnect actually runs. Retry state is likewise main-only.
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.scheduleReconnectAttempt(to: peer) }
            return
        }

        // Cancel any existing retry timer
        retryTimer?.invalidate()
        
        guard retryCount < maxRetries else {
            logger.error("Max retry attempts reached for peer: \(peer.displayName, privacy: .public)")
            retryCount = 0
            return
        }
        
        retryCount += 1
        // Actually exponential (the old `retryCount * 2` was linear), capped, and jittered
        // so several companions dropped by one Wi-Fi blip don't retry in lockstep.
        let backoff = min(pow(2.0, Double(retryCount)), Self.maxReconnectDelay)
        let delay = backoff + Double.random(in: 0...0.5)

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
