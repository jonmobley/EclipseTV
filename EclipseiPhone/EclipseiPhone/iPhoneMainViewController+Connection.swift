// iPhoneMainViewController+Connection.swift
import UIKit
import MultipeerConnectivity

// MARK: - Connection & Connection State UI

extension iPhoneMainViewController {

    /// The Apple TV (by device name) the user last chose to view. Auto-connect prefers
    /// it over the first-discovered peer. Nil means "no preference" (legacy behavior).
    var preferredTVName: String? {
        get { UserDefaults.standard.string(forKey: "EclipseTV.companion.preferredTVName") }
        set { UserDefaults.standard.set(newValue, forKey: "EclipseTV.companion.preferredTVName") }
    }

    /// Returns the discovered peer matching `preferredTVName`, if any.
    func preferredPeer(from peers: [MCPeerID]) -> MCPeerID? {
        guard let preferred = preferredTVName else { return nil }
        return peers.first(where: { $0.displayName == preferred })
    }

    func startSearching() {
        // Check if we already have a connection
        if isConnected() {
            // Already connected, just update UI
            updateConnectedState(true, peer: selectedPeer)
            return
        }

        // Update UI to show searching (disconnected until we actually connect).
        headerBar.setConnected(false)

        // Start browsing if not already browsing
        if !connectionManager.isBrowsing {
            connectionManager.startBrowsing()
        }

        // Create auto-connect timer that tries to find and connect to the first Apple TV every few seconds
        if autoConnectTimer == nil {
            autoConnectTimer = Timer.scheduledTimer(timeInterval: 2.0, target: self, selector: #selector(tryAutoConnect), userInfo: nil, repeats: true)
        }

        // If we still aren't connected after a grace period, surface troubleshooting help
        // (covers denied Local Network permission, wrong Wi-Fi, or TV app not open).
        scheduleConnectionHint()
    }

    // MARK: - Troubleshooting Hint

    /// Arms a one-shot timer that reveals the troubleshooting hint if we haven't connected.
    private func scheduleConnectionHint() {
        connectionHintTimer?.invalidate()
        connectionHintTimer = Timer.scheduledTimer(withTimeInterval: 12.0, repeats: false) { [weak self] _ in
            self?.showConnectionHint()
        }
    }

    private func showConnectionHint() {
        guard !isConnected() else { return }
        guard presentedViewController == nil else { return }
        logger.info("[Eclipse:CONN] iPhone no connection after grace period. discoveredPeers=\(self.connectionManager.discoveredPeers.count, privacy: .public), browsing=\(self.connectionManager.isBrowsing, privacy: .public)")
        DispatchQueue.main.async {
            guard !self.isConnected(), self.presentedViewController == nil else { return }
            let alert = UIAlertController(
                title: "Still connecting?",
                message: "Make sure the Eclipse app is open on your Apple TV, both devices are on the same Wi-Fi, and that Local Network access is enabled for Eclipse.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "Open Settings", style: .default) { [weak self] _ in
                self?.openAppSettings()
            })
            alert.addAction(UIAlertAction(title: "Keep Waiting", style: .cancel))
            self.present(alert, animated: true)
        }
    }

    /// Cancels the pending troubleshooting hint timer (e.g. once connected).
    func hideConnectionHint() {
        connectionHintTimer?.invalidate()
        connectionHintTimer = nil
    }

    /// Deep-links to Eclipse's page in Settings, where the Local Network toggle appears.
    @objc func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
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

        // Connect to the preferred Apple TV if it's discovered, otherwise the first
        // available peer. Only the Eclipse Apple TV app advertises the `eclipse-share`
        // service, so any discovered peer is an Eclipse TV regardless of its name.
        let peers = connectionManager.discoveredPeers
        if let peer = preferredPeer(from: peers) ?? peers.first {
            selectedPeer = peer
            connectionManager.invitePeer(peer)

            // Don't update UI state to connected until we actually connect.
            // Stop the timer safely
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
        }
    }

    func stopSearching() {
        connectionManager.stopBrowsing()

        // Clean invalidate timer safely
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        hideConnectionHint()
    }

    func updateConnectedState(_ connected: Bool, peer: MCPeerID?) {
        DispatchQueue.main.async {
            if connected, let peer = peer {
                // Connected: drop any pending troubleshooting hint and enable sending.
                self.hideConnectionHint()
                self.headerBar.setConnected(true)
                self.selectedPeer = peer
            } else {
                self.headerBar.setConnected(false)

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
