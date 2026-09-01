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
        logger.debug("Found peer: \(peer.displayName, privacy: .private)")
        refreshLibraryMenu()

        // Auto-connect only to already-paired Apple TVs, unless the user just entered a
        // pairing PIN (first-time pair). A rogue advertiser can't join without that PIN.
        if selectedPeer == nil {
            guard !isConnectionPaused else { return }
            let hasPIN = manager.pendingPairingPIN != nil
            guard manager.isPaired(with: peer) || hasPIN else {
                logger.debug("Discovered unpaired Apple TV; waiting for PIN entry: \(peer.displayName, privacy: .private)")
                return
            }
            if let preferred = preferredTVName, peer.displayName != preferred,
               manager.isPaired(with: peer) || !hasPIN {
                logger.debug("Holding out for preferred Apple TV: \(preferred, privacy: .private)")
                return
            }
            logger.debug("Attempting to connect to Apple TV: \(peer.displayName, privacy: .private)")
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
        // Align TV library bucket + transition preference, then flush that mode.
        let mode = ExternalOutputSettings.libraryMode
        connectionManager.sendSetDisplayMode(mode)
        connectionManager.sendSetContentTransition(
            ExternalOutputSettings.contentTransition.rawValue
        )
        connectionManager.sendSetLibraryAlbums(LibraryAlbumPush.currentAlbums())
        AirPlayOverlayPark.reparkIfNeeded(
            using: connectionManager,
            eclipseTVOnline: true,
            airPlayConnected: ExternalDisplayManager.shared.isConnected
        )
        let pendingCount = PendingUploadStore.shared.uploads(for: mode).count
        if pendingCount > 0 {
            showTemporaryStatus(
                "Syncing \(pendingCount) item\(pendingCount == 1 ? "" : "s") to Apple TV…"
            )
        }
        connectionManager.flushPendingUploads(for: mode)
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
