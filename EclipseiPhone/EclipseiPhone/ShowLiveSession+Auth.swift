//
//  ShowLiveSession+Auth.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity

// MARK: - Mutual check after connecting

/// Every connected peer must pass ``ShowLivePeerHandshake`` before anything it
/// sends is used or anything is sent to it. Peers that send a bad proof, or
/// none within ``handshakeTimeout``, are disconnected.
extension ShowLiveSession {

    /// How long a connected peer has to prove itself.
    static let handshakeTimeout: Duration = .seconds(10)

    /// Starts the check with a newly connected peer (or answers its hello).
    func beginHandshake(with peer: MCPeerID) {
        guard peerHandshakes[peer] == nil else { return }
        guard let userKey else {
            rejectPeer(peer, reason: "no account key")
            return
        }
        let handshake = ShowLivePeerHandshake(
            localRole: role == .director ? .director : .joiner,
            localName: peerID.displayName,
            peerName: peer.displayName,
            key: userKey
        )
        peerHandshakes[peer] = handshake
        sendSecure(handshake.hello, to: peer)
        scheduleHandshakeTimeout(peer, nonce: handshake.localNonce)
    }

    /// Handles one data message from the session.
    func handleIncoming(_ data: Data, from peer: MCPeerID) {
        guard let message = try? JSONDecoder().decode(ShowLiveSecureMessage.self, from: data)
        else { return }
        switch message.kind {
        case .hello: handleHello(message, from: peer)
        case .proof: handleProof(message, from: peer)
        case .sealed: handleSealed(message, from: peer)
        }
    }

    /// Seals `envelope` separately for each verified peer and sends it.
    /// - Returns: True when at least one peer was sent it.
    func sendToVerifiedPeers(_ envelope: ShowLiveEnvelope) -> Bool {
        guard let session, let plaintext = try? JSONEncoder().encode(envelope)
        else { return false }
        var sentAny = false
        for peer in session.connectedPeers {
            guard var handshake = peerHandshakes[peer], handshake.isPeerVerified,
                  let sealed = handshake.seal(plaintext)
            else { continue }
            peerHandshakes[peer] = handshake
            if sendSecure(sealed, to: peer) { sentAny = true }
        }
        return sentAny
    }

    // MARK: - Private Helpers

    private func handleHello(_ message: ShowLiveSecureMessage, from peer: MCPeerID) {
        beginHandshake(with: peer)
        guard var handshake = peerHandshakes[peer] else { return }
        switch handshake.receiveHello(message) {
        case .reply(let proof):
            peerHandshakes[peer] = handshake
            sendSecure(proof, to: peer)
        case .sameRole:
            // Another operator in the mesh: never trusted, but not dropped.
            peerHandshakes[peer] = nil
        case .refused:
            rejectPeer(peer, reason: "bad hello")
        }
    }

    private func handleProof(_ message: ShowLiveSecureMessage, from peer: MCPeerID) {
        guard var handshake = peerHandshakes[peer] else { return }
        guard handshake.receiveProof(message), let peerRole = handshake.peerRole else {
            rejectPeer(peer, reason: "bad proof")
            return
        }
        peerHandshakes[peer] = handshake
        logger.info("Show live peer verified \(peer.displayName, privacy: .public)")
        peerDidAuthenticate(peer, peerRole: peerRole)
    }

    private func handleSealed(_ message: ShowLiveSecureMessage, from peer: MCPeerID) {
        guard var handshake = peerHandshakes[peer],
              let plaintext = handshake.open(message)
        else { return }
        peerHandshakes[peer] = handshake
        guard let envelope = try? JSONDecoder().decode(ShowLiveEnvelope.self, from: plaintext)
        else { return }
        applyReceived(envelope, from: peer)
    }

    @discardableResult
    private func sendSecure(_ message: ShowLiveSecureMessage, to peer: MCPeerID) -> Bool {
        guard let session, let data = try? JSONEncoder().encode(message) else { return false }
        do {
            try session.send(data, toPeers: [peer], with: .reliable)
            return true
        } catch {
            logger.error("Show live send failed: \(error.localizedDescription)")
            return false
        }
    }

    private func rejectPeer(_ peer: MCPeerID, reason: String) {
        peerHandshakes[peer] = nil
        session?.cancelConnectPeer(peer)
        logger.error(
            "Show live dropped \(peer.displayName, privacy: .public): \(reason, privacy: .public)"
        )
    }

    private func scheduleHandshakeTimeout(_ peer: MCPeerID, nonce: String) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.handshakeTimeout)
            guard let self, let handshake = self.peerHandshakes[peer],
                  handshake.localNonce == nonce, !handshake.isPeerVerified
            else { return }
            self.rejectPeer(peer, reason: "no proof in time")
        }
    }
}

// MARK: - MCSessionDelegate

extension ShowLiveSession: MCSessionDelegate {
    nonisolated func session(
        _ session: MCSession,
        peer peerID: MCPeerID,
        didChange state: MCSessionState
    ) {
        Task { @MainActor in
            self.handlePeerState(state, peer: peerID)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive data: Data,
        fromPeer peerID: MCPeerID
    ) {
        Task { @MainActor in
            self.handleIncoming(data, from: peerID)
        }
    }

    nonisolated func session(
        _ session: MCSession,
        didReceive stream: InputStream,
        withName streamName: String,
        fromPeer peerID: MCPeerID
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didStartReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        with progress: Progress
    ) {}

    nonisolated func session(
        _ session: MCSession,
        didFinishReceivingResourceWithName resourceName: String,
        fromPeer peerID: MCPeerID,
        at localURL: URL?,
        withError error: (any Error)?
    ) {}
}
