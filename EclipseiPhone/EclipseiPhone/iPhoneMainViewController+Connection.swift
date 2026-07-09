//
//  iPhoneMainViewController+Connection.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

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

        // Honor the user's choice to use the app offline: don't browse, auto-connect,
        // or nag with the troubleshooting hint until they ask to reconnect.
        guard !isConnectionPaused else {
            headerBar.setConnectionState(.paused)
            return
        }

        // Update UI to show searching (disconnected until we actually connect).
        headerBar.setConnectionState(.disconnected)

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
            alert.addAction(UIAlertAction(title: "Use Without Apple TV", style: .default) { [weak self] _ in
                self?.pauseConnection()
            })
            alert.addAction(UIAlertAction(title: "Keep Waiting", style: .cancel))
            self.present(alert, animated: true)
        }
    }

    // MARK: - Pause / Resume

    /// Suspends all connection attempts so the user can browse their cached library
    /// offline. Reconnect on demand from the status pill or the "…" menu. Session-only.
    func pauseConnection() {
        isConnectionPaused = true
        connectionManager.autoConnectEnabled = false
        stopSearching()
        headerBar.setConnectionState(.paused)
        showTemporaryStatus("Using Eclipse without Apple TV. Tap “Offline” or the … menu to connect.")
    }

    /// Re-enables auto-connect. If any discovered TV is already paired, starts searching
    /// immediately; otherwise prompts for the pairing code shown on the Apple TV.
    func resumeConnection() {
        guard !isConnected() else { return }
        isConnectionPaused = false
        connectionManager.autoConnectEnabled = true
        selectedPeer = nil

        let peers = connectionManager.discoveredPeers
        if peers.contains(where: { connectionManager.isPaired(with: $0) }) {
            startSearching()
            return
        }
        presentPairingPINEntry()
    }

    /// Asks the user for the 6-digit code displayed on the Apple TV, then invites.
    func presentPairingPINEntry(for peer: MCPeerID? = nil) {
        let alert = UIAlertController(
            title: "Pair with Apple TV",
            message: "Enter the 6-digit pairing code shown in the Eclipse app on your Apple TV.",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "000000"
            field.keyboardType = .numberPad
            field.textContentType = .oneTimeCode
            field.autocorrectionType = .no
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { [weak self] _ in
            self?.connectionManager.clearPendingPairingPIN()
        })
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let pin = PeerPairing.normalizePIN(raw)
            guard PeerPairing.isValidPIN(pin) else {
                self.showAlert(title: "Invalid Code",
                               message: "Enter the 6-digit pairing code shown on your Apple TV.")
                return
            }
            self.connectionManager.setPendingPairingPIN(pin)
            self.startSearching()
            let target = peer
                ?? self.preferredPeer(from: self.connectionManager.discoveredPeers)
                ?? self.connectionManager.discoveredPeers.first
            if let target {
                self.selectedPeer = target
                self.connectionManager.invitePeer(target)
            }
        })
        present(alert, animated: true)
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
        // Stop auto-connecting while the user is using the app offline.
        if isConnectionPaused {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            return
        }

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

        // Prefer a paired preferred TV, then any paired peer. With a pending PIN, also
        // allow inviting the preferred/first unpaired peer for first-time pairing.
        let peers = connectionManager.discoveredPeers
        let paired = peers.filter { connectionManager.isPaired(with: $0) }
        let hasPIN = connectionManager.pendingPairingPIN != nil
        let candidates = paired.isEmpty && hasPIN ? peers : paired
        if let peer = preferredPeer(from: candidates) ?? candidates.first {
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
                // A live connection always clears the paused state.
                self.hideConnectionHint()
                self.isConnectionPaused = false
                self.connectionManager.autoConnectEnabled = true
                self.selectedPeer = peer
                self.headerBar.setConnectionState(.connected)
            } else {
                // Only clear selectedPeer if explicitly told to
                if peer == nil {
                    self.selectedPeer = nil
                }
                // Preserve the offline pill while paused; otherwise show disconnected.
                self.headerBar.setConnectionState(self.isConnectionPaused ? .paused : .disconnected)
            }
        }
    }

    func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        present(alertController, animated: true)
    }
}
