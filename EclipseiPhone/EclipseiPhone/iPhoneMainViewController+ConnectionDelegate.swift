//
//  iPhoneMainViewController+ConnectionDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

// iPhoneMainViewController+ConnectionDelegate.swift
import UIKit
import MultipeerConnectivity
import os

// MARK: - iPhoneConnectionManagerDelegate

extension iPhoneMainViewController: iPhoneConnectionManagerDelegate {
    func connectionManager(_ manager: iPhoneConnectionManager, didFindPeer peer: MCPeerID) {
        logger.debug("Found peer: \(peer.displayName, privacy: .public)")
        refreshLibraryMenu()

        // Auto-connect when we don't already have a peer. If the user has a preferred
        // Apple TV, hold out for it; the auto-connect timer falls back to the first
        // discovered peer if the preferred one never appears. Only the Eclipse Apple TV
        // app advertises `eclipse-share`, so any discovered peer is an Eclipse TV.
        if selectedPeer == nil {
            // Don't auto-invite while the user has chosen to stay offline.
            guard !isConnectionPaused else { return }
            if let preferred = preferredTVName, peer.displayName != preferred {
                logger.debug("Holding out for preferred Apple TV: \(preferred, privacy: .public)")
                return
            }
            logger.debug("Attempting to connect to Apple TV: \(peer.displayName, privacy: .public)")
            selectedPeer = peer
            connectionManager.invitePeer(peer)
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didLosePeer peer: MCPeerID) {
        refreshLibraryMenu()
        if selectedPeer == peer {
            if !isShowingPicker {
                updateConnectedState(false, peer: nil)
                startSearching()
            }
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didConnectToPeer peer: MCPeerID) {
        // Remember the connected TV as the preferred one and reflect it in the header.
        preferredTVName = peer.displayName
        updateConnectedState(true, peer: peer)
        refreshLibraryMenu()
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didDisconnectFromPeer peer: MCPeerID) {
        refreshLibraryMenu()
        if selectedPeer == peer {
            // Only update UI and restart searching if we're not in the middle of picking images
            if !isShowingPicker {
                updateConnectedState(false, peer: nil)
                startSearching()
            }
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveConfirmationFromPeer peer: MCPeerID) {
        DispatchQueue.main.async {
            self.showTemporaryStatus("Sent successfully!", duration: 3.0)
            self.hideTransferUI() // This will now clean up temp files
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateVideoTransferProgress progress: Double) {
        // Update status label with progress
        statusLabel.text = String(format: "Sending video: %.1f%%", progress)
        statusLabel.alpha = 1.0

        // If transfer is complete, show completion message and hide transfer UI
        if progress >= 100.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.statusLabel.text = "Video sent successfully"
                self.hideTransferUI()

                // Fade out status after 3 seconds
                UIView.animate(withDuration: 0.5, delay: 3.0, options: [], animations: {
                    self.statusLabel.alpha = 0
                })
            }
        }
    }

    // Add delegate method for image progress
    func connectionManager(_ manager: iPhoneConnectionManager, didUpdateImageTransferProgress progress: Double) {
        statusLabel.text = String(format: "Sending image: %.1f%%", progress)
        statusLabel.alpha = 1.0
        if progress >= 100.0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
                guard let self = self else { return }
                self.statusLabel.text = "Image sent successfully"
                self.hideTransferUI()
                UIView.animate(withDuration: 0.5, delay: 3.0, options: [], animations: {
                    self.statusLabel.alpha = 0
                })
            }
        }
    }

    // Handle a failed media transfer with a clear, user-facing error
    func connectionManager(_ manager: iPhoneConnectionManager, didFailTransferIsVideo isVideo: Bool, error: Error?) {
        DispatchQueue.main.async {
            self.hideTransferUI()

            let mediaType = isVideo ? "video" : "image"
            let detail = error?.localizedDescription ?? "The connection may have been interrupted."
            self.showAlert(title: "Transfer Failed", message: "Could not send the \(mediaType). \(detail)")
        }
    }

    // Handle move mode state changes from Apple TV
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveMoveModeState enabled: Bool) {
        DispatchQueue.main.async {
            if enabled {
                self.showTemporaryStatus("AppleTV is organizing content. Your media will be added when complete.", duration: 5.0)
            } else {
                self.showTemporaryStatus("AppleTV is ready to receive media again", duration: 3.0)
            }
        }
    }
}
