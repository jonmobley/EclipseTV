//
//  ShowLiveSession+Advertise.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity
import UIKit

// MARK: - Director advertising

extension ShowLiveSession {
    /// Starts advertising this device as director for `showId`.
    func startAdvertising(showId: UUID) {
        guard let userHash else { return }
        stopBrowsing()
        stopElection()
        if isAdvertising, openingShowId == showId { return }
        stopAdvertising()
        openingShowId = showId
        setRole(.director)
        setDirectorDeviceName(UIDevice.current.name)
        let info: [String: String] = [
            ShowLiveProtocol.discoveryShowId: showId.uuidString,
            ShowLiveProtocol.discoveryUserHash: userHash,
            ShowLiveProtocol.discoveryDeviceName: ShowLiveRouting.shortDeviceName(
                UIDevice.current.name
            )
        ]
        let advertiser = MCNearbyServiceAdvertiser(
            peer: peerID,
            discoveryInfo: info,
            serviceType: ShowLiveProtocol.serviceType
        )
        advertiser.delegate = self
        self.advertiser = advertiser
        advertiser.startAdvertisingPeer()
        isAdvertising = true
        _ = ensureSession()
        logger.info("Show live advertising \(showId.uuidString, privacy: .public)")
        notifyChanged()
    }

    /// Stops Bonjour advertising without tearing down connected operators.
    func stopAdvertising() {
        advertiser?.stopAdvertisingPeer()
        advertiser = nil
        isAdvertising = false
    }

    func shouldAcceptInvitation(context: Data?) -> Bool {
        guard role == .director || isAdvertising,
              let userHash, let showId = openingShowId,
              let context,
              let invite = try? JSONDecoder().decode(
                ShowLiveInvitation.self, from: context
              )
        else { return false }
        return ShowLiveRouting.canAutoJoin(
            advertisedShowId: invite.showId,
            advertisedUserHash: invite.userHash,
            localShowId: showId,
            localUserHash: userHash
        )
    }
}

extension ShowLiveSession: MCNearbyServiceAdvertiserDelegate {
    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didReceiveInvitationFromPeer peerID: MCPeerID,
        withContext context: Data?,
        invitationHandler: @escaping (Bool, MCSession?) -> Void
    ) {
        Task { @MainActor in
            let ok = self.shouldAcceptInvitation(context: context)
            if ok { _ = self.ensureSession() }
            invitationHandler(ok, ok ? self.session : nil)
        }
        _ = peerID
    }

    nonisolated func advertiser(
        _ advertiser: MCNearbyServiceAdvertiser,
        didNotStartAdvertisingPeer error: Error
    ) {
        Task { @MainActor in
            self.logger.error(
                "Show live advertise failed: \(error.localizedDescription)"
            )
        }
    }
}
