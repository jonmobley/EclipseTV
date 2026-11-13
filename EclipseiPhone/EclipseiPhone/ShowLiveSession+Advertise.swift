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
        let challenge = ShowLiveInviteProof.newChallenge()
        advertisedChallenge = challenge
        let info: [String: String] = [
            ShowLiveProtocol.discoveryChallenge: challenge,
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
        advertisedChallenge = nil
    }

    func shouldAcceptInvitation(context: Data?) -> Bool {
        guard role == .director || isAdvertising,
              let userHash, let userKey, let showId = openingShowId,
              let challenge = advertisedChallenge,
              let context,
              let invite = try? JSONDecoder().decode(
                ShowLiveInvitation.self, from: context
              ),
              let nonce = invite.nonce,
              ShowLiveInviteProof.isWellFormedNonce(nonce),
              !usedInviteNonces.contains(nonce)
        else { return false }
        let valid = ShowLiveRouting.canAutoJoin(
            advertisedShowId: invite.showId,
            advertisedUserHash: invite.userHash,
            localShowId: showId,
            localUserHash: userHash
        ) && ShowLiveInviteProof.isValid(
            proof: invite.proof, challenge: challenge, showId: showId,
            nonce: nonce, key: userKey
        )
        // Remember only proven nonces, so strangers cannot grow the set.
        if valid { usedInviteNonces.insert(nonce) }
        return valid
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
