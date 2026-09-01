//
//  ShowLiveSession+Browser.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity

// MARK: - Operator browse / election

extension ShowLiveSession {
    /// Browses for a director of the open Show.
    func startBrowsing(showId: UUID) {
        guard userHash != nil else { return }
        if isBrowsing, openingShowId == showId { return }
        stopBrowsing()
        openingShowId = showId
        let browser = MCNearbyServiceBrowser(
            peer: peerID, serviceType: ShowLiveProtocol.serviceType
        )
        browser.delegate = self
        self.browser = browser
        browser.startBrowsingForPeers()
        isBrowsing = true
        logger.info("Show live browsing \(showId.uuidString, privacy: .public)")
    }

    func stopBrowsing() {
        browser?.stopBrowsingForPeers()
        browser = nil
        isBrowsing = false
    }

    /// Waits briefly for an existing director before this HDMI device advertises.
    func scheduleElection(showId: UUID) {
        if foundDirector { return }
        stopElection()
        electionTimer = Timer.scheduledTimer(
            withTimeInterval: ShowLiveRouting.electionWindow, repeats: false
        ) { [weak self] _ in
            Task { @MainActor in
                self?.finishElection(showId: showId)
            }
        }
    }

    func stopElection() {
        electionTimer?.invalidate()
        electionTimer = nil
    }

    func finishElection(showId: UUID) {
        electionTimer = nil
        guard openingShowId == showId, role == .none else { return }
        let hasDisplay = ExternalDisplayManager.shared.isConnected
        if ShowLiveRouting.shouldBecomeDirectorAfterElection(
            foundDirector: foundDirector,
            hasExternalDisplay: hasDisplay,
            isRemoteOperator: false
        ) {
            startAdvertising(showId: showId)
        }
    }

    func inviteDirector(_ peer: MCPeerID, info: [String: String]) {
        guard let userHash, let showId = openingShowId, role != .director else {
            return
        }
        let advertisedShow = UUID(uuidString: info[ShowLiveProtocol.discoveryShowId] ?? "")
        let advertisedUser = info[ShowLiveProtocol.discoveryUserHash]
        guard ShowLiveRouting.canAutoJoin(
            advertisedShowId: advertisedShow,
            advertisedUserHash: advertisedUser,
            localShowId: showId,
            localUserHash: userHash
        ) else { return }
        foundDirector = true
        stopElection()
        let invite = ShowLiveInvitation(showId: showId, userHash: userHash)
        guard let context = try? JSONEncoder().encode(invite) else { return }
        setDirectorDeviceName(
            info[ShowLiveProtocol.discoveryDeviceName] ?? peer.displayName
        )
        let session = ensureSession()
        browser?.invitePeer(peer, to: session, withContext: context, timeout: 12)
        logger.info("Show live inviting \(peer.displayName, privacy: .public)")
    }
}

extension ShowLiveSession: MCNearbyServiceBrowserDelegate {
    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        foundPeer peerID: MCPeerID,
        withDiscoveryInfo info: [String: String]?
    ) {
        Task { @MainActor in
            guard peerID != self.peerID, let info else { return }
            self.inviteDirector(peerID, info: info)
        }
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        lostPeer peerID: MCPeerID
    ) {
        _ = peerID
    }

    nonisolated func browser(
        _ browser: MCNearbyServiceBrowser,
        didNotStartBrowsingForPeers error: Error
    ) {
        Task { @MainActor in
            self.logger.error(
                "Show live browse failed: \(error.localizedDescription)"
            )
        }
    }
}
