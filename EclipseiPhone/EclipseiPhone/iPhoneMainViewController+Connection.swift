// iPhoneMainViewController+Connection.swift
import UIKit
import MultipeerConnectivity

// MARK: - Connection & Connection State UI

extension iPhoneMainViewController {

    func startSearching() {
        // Check if we already have a connection
        if isConnected() {
            // Already connected, just update UI
            updateConnectedState(true, peer: selectedPeer)
            return
        }

        // Update UI to show searching
        connectionStatusIcon.tintColor = .lightGray
        connectionStatusLabel.text = "Connecting..."
        connectionStatusLabel.textColor = .lightGray
        subtitleLabel.text = "Open the Eclipse app on your AppleTV to connect"
        connectionActivityIndicator.startAnimating()

        // Start browsing if not already browsing
        if !connectionManager.isBrowsing {
            connectionManager.startBrowsing()
        }

        // Create auto-connect timer that tries to find and connect to the first Apple TV every few seconds
        if autoConnectTimer == nil {
            autoConnectTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(tryAutoConnect), userInfo: nil, repeats: true)
        }
    }

    @objc private func tryAutoConnect() {
        // If we already have a selected peer and it's connected, no need to auto-connect
        if isConnected() {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            return
        }

        // If we have a selected peer but it's not connected, try to invite it
        if let peer = selectedPeer {
            // Only invite if we're not already connected to them
            if !connectionManager.isConnectedToPeer(peer) {
                connectionManager.invitePeer(peer)
            }
            return
        }

        // Try to connect to any available Apple TV peer
        for peer in connectionManager.discoveredPeers {
            if peer.displayName.contains("Apple TV") || peer.displayName.contains("AppleTV") {
                selectedPeer = peer
                connectionManager.invitePeer(peer)

                // Don't update UI state to connected until we actually connect
                // Just update status to show we're trying to connect
                DispatchQueue.main.async {
                    self.connectionStatusLabel.text = "Connecting to \(peer.displayName)..."
                }

                // Stop the timer safely
                autoConnectTimer?.invalidate()
                autoConnectTimer = nil
                break
            }
        }
    }

    func stopSearching() {
        connectionManager.stopBrowsing()
        connectionActivityIndicator.stopAnimating()

        // Clean invalidate timer safely
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
    }

    func updateConnectedState(_ connected: Bool, peer: MCPeerID?) {
        DispatchQueue.main.async {
            if connected, let peer = peer {
                // Update connected UI
                UIView.animate(withDuration: 0.3) {
                    self.connectionStatusIcon.alpha = 1
                    self.connectionActivityIndicator.alpha = 0
                }
                self.connectionActivityIndicator.stopAnimating()
                self.connectionStatusIcon.tintColor = .systemGreen
                self.connectionStatusLabel.text = "Connected"
                self.connectionStatusLabel.textColor = .systemGreen
                self.subtitleLabel.text = "Keep the Eclipse AppleTV app open to stay connected."

                // Enable media picker button when connected
                self.mediaPickerButton.isEnabled = true
                self.mediaPickerButton.alpha = 1.0
                self.mediaPickerButton.backgroundColor = .systemBlue

                // Update selectedPeer
                self.selectedPeer = peer
            } else {
                // Update disconnected UI
                UIView.animate(withDuration: 0.3) {
                    self.connectionStatusIcon.alpha = 0
                    self.connectionActivityIndicator.alpha = 1
                }
                self.connectionActivityIndicator.startAnimating()
                self.connectionStatusIcon.tintColor = .lightGray
                self.connectionStatusLabel.text = "Connecting..."
                self.connectionStatusLabel.textColor = .lightGray
                self.subtitleLabel.text = "Open the Eclipse app on your AppleTV to connect"

                // Disable media picker button when disconnected
                self.mediaPickerButton.isEnabled = false
                self.mediaPickerButton.alpha = 0.5
                self.mediaPickerButton.backgroundColor = .lightGray

                // Only clear selectedPeer if explicitly told to
                if peer == nil {
                    self.selectedPeer = nil
                }
            }
        }
    }

    func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
