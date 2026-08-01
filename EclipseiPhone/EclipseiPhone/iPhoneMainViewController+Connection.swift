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
        get { CompanionSettings.preferredTVName }
        set { CompanionSettings.preferredTVName = newValue }
    }

    /// Returns the discovered peer matching `preferredTVName`, if any.
    func preferredPeer(from peers: [MCPeerID]) -> MCPeerID? {
        guard let preferred = preferredTVName else { return nil }
        return peers.first(where: { $0.displayName == preferred })
    }

    func startSearching() {
        // Check if we already have a connection
        if isConnected() {
            updateConnectedState(true, peer: selectedPeer)
            return
        }

        // Don't browse or auto-connect until the user asks (AirPlay-first default).
        guard !isConnectionPaused else {
            headerBar.setConnectionState(.paused)
            return
        }

        headerBar.setConnectionState(.disconnected)

        if !connectionManager.isBrowsing {
            connectionManager.startBrowsing()
        }

        if autoConnectTimer == nil {
            autoConnectTimer = Timer.scheduledTimer(
                timeInterval: 2.0,
                target: self,
                selector: #selector(tryAutoConnect),
                userInfo: nil,
                repeats: true
            )
        }
    }

    // MARK: - Pause / Resume

    /// Suspends Multipeer connection attempts to EclipseTV.
    /// AirPlay for Camera/Web still works. Reconnect from Settings → EclipseTV.
    func pauseConnection(announce: Bool = true) {
        isConnectionPaused = true
        connectionManager.autoConnectEnabled = false
        stopSearching()
        headerBar.setConnectionState(.paused)
        if announce {
            showTemporaryStatus("Stopped EclipseTV link. AirPlay is unchanged.")
        }
    }

    /// Starts linking to EclipseTV. If a paired TV is already known, begins
    /// searching; otherwise prompts for the pairing code shown on the Apple TV.
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

    /// Asks for the 6-digit code shown in the Eclipse app on Apple TV, then invites.
    func presentPairingPINEntry(for peer: MCPeerID? = nil) {
        let alert = UIAlertController(
            title: "Connect EclipseTV",
            message: "Enter the 6-digit code from the Eclipse app on Apple TV. This is not AirPlay pairing.",
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
            // Pairing is opt-in; cancel returns to the AirPlay-first idle state.
            self?.pauseConnection(announce: false)
        })
        alert.addAction(UIAlertAction(title: "Connect", style: .default) { [weak self] _ in
            guard let self else { return }
            let raw = alert.textFields?.first?.text ?? ""
            let pin = PeerPairing.normalizePIN(raw)
            guard PeerPairing.isValidPIN(pin) else {
                self.showAlert(
                    title: "Invalid Code",
                    message: "Enter the 6-digit code shown in the Eclipse app on your Apple TV."
                )
                self.pauseConnection(announce: false)
                return
            }
            self.isConnectionPaused = false
            self.connectionManager.autoConnectEnabled = true
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
        presentationAnchor.present(alert, animated: true)
    }

    /// Cancels any leftover troubleshooting hint timer.
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
        if isConnectionPaused {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            return
        }

        if isConnected() {
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
            return
        }

        if let peer = selectedPeer {
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
            autoConnectTimer?.invalidate()
            autoConnectTimer = nil
        }
    }

    func stopSearching() {
        connectionManager.stopBrowsing()
        autoConnectTimer?.invalidate()
        autoConnectTimer = nil
        hideConnectionHint()
    }

    func updateConnectedState(_ connected: Bool, peer: MCPeerID?) {
        DispatchQueue.main.async {
            if connected, let peer = peer {
                self.hideConnectionHint()
                self.isConnectionPaused = false
                self.connectionManager.autoConnectEnabled = true
                self.selectedPeer = peer
                self.headerBar.setConnectionState(.connected)
            } else {
                if peer == nil {
                    self.selectedPeer = nil
                }
                self.headerBar.setConnectionState(self.isConnectionPaused ? .paused : .disconnected)
            }
        }
    }

    func showAlert(title: String, message: String) {
        let alertController = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alertController.addAction(UIAlertAction(title: "OK", style: .default))
        presentationAnchor.present(alertController, animated: true)
    }

    /// Header output-status control: explains AirPlay vs EclipseTV and offers Link.
    func presentOutputStatusOptions() {
        let airPlay = ExternalDisplayManager.shared.isConnected
        let linked = isConnected()
        let searching = !isConnectionPaused && !linked
        let sheet = UIAlertController(
            title: "Output",
            message: Self.outputStatusMessage(
                airPlay: airPlay,
                linked: linked,
                searching: searching
            ),
            preferredStyle: .actionSheet
        )
        if !linked {
            sheet.addAction(UIAlertAction(title: "Link EclipseTV…", style: .default) { [weak self] _ in
                self?.resumeConnection()
            })
        }
        if !airPlay {
            sheet.addAction(
                UIAlertAction(title: "How to AirPlay", style: .default) { [weak self] _ in
                    self?.showAlert(
                        title: "AirPlay",
                        message: "Open Control Center, tap Screen Mirroring, and choose "
                            + "your display. AirPlay is enough to present a Show — "
                            + "linking EclipseTV is only for media sync."
                    )
                }
            )
        }
        sheet.addAction(UIAlertAction(title: "EclipseTV Settings", style: .default) { [weak self] _ in
            self?.presentSettings(focusEclipseTV: true)
        })
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        if let popover = sheet.popoverPresentationController {
            popover.sourceView = headerBar.outputStatusButton
            popover.sourceRect = headerBar.outputStatusButton.bounds
        }
        present(sheet, animated: true)
    }

    private static func outputStatusMessage(
        airPlay: Bool,
        linked: Bool,
        searching: Bool
    ) -> String {
        var parts: [String] = []
        parts.append(airPlay ? "AirPlay: connected" : "AirPlay: not connected")
        if linked {
            parts.append("EclipseTV: linked")
        } else if searching {
            parts.append("EclipseTV: connecting…")
        } else {
            parts.append("EclipseTV: not linked")
        }
        parts.append(
            "AirPlay presents your Show. EclipseTV link syncs media with the TV app."
        )
        return parts.joined(separator: "\n")
    }
}
