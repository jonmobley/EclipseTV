// iPhoneMainViewController+ConnectionDelegate.swift
import UIKit
import MultipeerConnectivity
import os

// MARK: - iPhoneConnectionManagerDelegate

extension iPhoneMainViewController: iPhoneConnectionManagerDelegate {
    func connectionManager(_ manager: iPhoneConnectionManager, didFindPeer peer: MCPeerID) {
        logger.debug("Found peer: \(peer.displayName, privacy: .public)")

        // Auto-connect to Apple TV peers if we don't already have a connection
        if selectedPeer == nil && (peer.displayName.contains("Apple TV") || peer.displayName.contains("AppleTV")) {
            logger.debug("Attempting to connect to Apple TV: \(peer.displayName, privacy: .public)")
            selectedPeer = peer
            connectionManager.invitePeer(peer)

            // Update UI to show we're attempting to connect
            DispatchQueue.main.async {
                self.connectionStatusLabel.text = "Connecting to \(peer.displayName)..."
            }
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didLosePeer peer: MCPeerID) {
        if selectedPeer == peer {
            if !isShowingPicker {
                updateConnectedState(false, peer: nil)
                startSearching()
            }
        }
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didConnectToPeer peer: MCPeerID) {
        updateConnectedState(true, peer: peer)
    }

    func connectionManager(_ manager: iPhoneConnectionManager, didDisconnectFromPeer peer: MCPeerID) {
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
            self.connectionActivityIndicator.stopAnimating()
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
                self.connectionActivityIndicator.stopAnimating()

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
                self.connectionActivityIndicator.stopAnimating()
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
            self.connectionActivityIndicator.stopAnimating()

            let mediaType = isVideo ? "video" : "image"
            let detail = error?.localizedDescription ?? "The connection may have been interrupted."
            self.showAlert(title: "Transfer Failed", message: "Could not send the \(mediaType). \(detail)")
        }
    }

    // Handle move mode state changes from Apple TV
    func connectionManager(_ manager: iPhoneConnectionManager, didReceiveMoveModeState enabled: Bool) {
        DispatchQueue.main.async {
            if enabled {
                // Show notification that AppleTV is in move mode
                self.showTemporaryStatus("AppleTV is organizing content. Your media will be added when complete.", duration: 5.0)

                // Update button state to indicate move mode (optional)
                if self.mediaPickerButton.isEnabled {
                    self.mediaPickerButton.setTitle("Waiting...", for: .normal)
                }
            } else {
                // Show notification that AppleTV has exited move mode
                self.showTemporaryStatus("AppleTV is ready to receive media again", duration: 3.0)

                // Restore button state
                if self.mediaPickerButton.isEnabled {
                    self.mediaPickerButton.setTitle("Send Media", for: .normal)
                }
            }
        }
    }
}
