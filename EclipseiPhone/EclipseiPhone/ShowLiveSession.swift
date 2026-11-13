//
//  ShowLiveSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import CryptoKit
import Foundation
import MultipeerConnectivity
import os.log
import UIKit

/// Local-network live session: the HDMI device is director, other phones that
/// open the same Show are operators. CloudKit is not used for live commands.
@MainActor
final class ShowLiveSession: NSObject {
    /// Shared session for the running app.
    static let shared = ShowLiveSession()

    /// Posted when role, snapshot, or director name changes.
    static let didChangeNotification = Notification.Name("ShowLiveSession.didChange")
    /// Posted on the director when an operator sends `select`.
    static let incomingSelectNotification = Notification.Name(
        "ShowLiveSession.incomingSelect"
    )
    /// `ShowLiveItemKind.rawValue` on `incomingSelectNotification`.
    static let selectKindKey = "kind"
    /// Optional item id on `incomingSelectNotification`.
    static let selectItemIdKey = "itemId"
    /// Posted on the director when an operator sends a `command`.
    static let incomingCommandNotification = Notification.Name(
        "ShowLiveSession.incomingCommand"
    )
    /// `ShowLiveCommand` on `incomingCommandNotification`.
    static let commandKey = "command"
    /// `Bool` on `didChangeNotification`: false when only a video / clock tick
    /// changed, so observers can skip the grid rebuild.
    static let programChangedKey = "programChanged"

    /// Director (owns HDMI), remote operator (commands director), or neither.
    enum Role: Equatable {
        case none
        case director
        case remote
    }

    private(set) var role: Role = .none
    private(set) var snapshot: ShowLiveSnapshot?
    private(set) var directorDeviceName: String?
    private(set) var userHash: String?
    /// Key from the iCloud Keychain account secret (``ShowLiveAccountSecret``)
    /// proving this phone belongs to the owner; memory only. Nil keeps Show
    /// Live off.
    private(set) var userKey: SymmetricKey?
    /// Per-peer mutual check and sealing state (``ShowLivePeerHandshake``).
    var peerHandshakes: [MCPeerID: ShowLivePeerHandshake] = [:]
    /// Challenge in this director's current discovery info.
    var advertisedChallenge: String? { didSet { usedInviteNonces = [] } }
    /// Invitation nonces already accepted for that challenge.
    var usedInviteNonces: Set<String> = []

    /// Updates role from advertising / browsing extensions in this module.
    func setRole(_ role: Role) {
        self.role = role
    }

    /// Updates the director device label shown to remotes.
    func setDirectorDeviceName(_ name: String?) {
        directorDeviceName = name
    }

    /// True when this device's Show grid should command another device's program.
    var isRemoteOperator: Bool { role == .remote }
    /// True when this device owns HDMI/AirPlay for the open Show.
    var isDirector: Bool { role == .director }

    let logger = Logger(subsystem: "com.eclipseapp.ios", category: "ShowLive")
    let peerID: MCPeerID
    var session: MCSession?
    var advertiser: MCNearbyServiceAdvertiser?
    var browser: MCNearbyServiceBrowser?
    var electionTimer: Timer?
    var openingShowId: UUID?
    var foundDirector: Bool = false
    var isAdvertising = false
    var isBrowsing = false

    override init() {
        peerID = MCPeerID(displayName: UIDevice.current.name)
        super.init()
    }

    /// Prefetches the CloudKit user hash so opening a Show can join quickly.
    func prepare() {
        refreshCloudKitUser()
    }

    /// Aligns advertising / browsing with the open Show and HDMI state.
    func sync(openShowId: UUID?) {
        if openShowId != openingShowId {
            tearDownSession()
            openingShowId = openShowId
            foundDirector = false
        }
        guard let showId = openShowId else {
            tearDownSession()
            openingShowId = nil
            return
        }
        refreshCloudKitUser { [weak self] in
            self?.continueSync(showId: showId)
        }
    }

    /// Sends a tile select to the director. Returns false when this device is not
    /// an operator or the send failed.
    @discardableResult
    func sendSelect(kind: ShowLiveItemKind, itemId: String?) -> Bool {
        guard role == .remote else { return false }
        let envelope = ShowLiveEnvelope(
            kind: .select, itemKind: kind, itemId: itemId, snapshot: nil
        )
        return send(envelope)
    }

    /// Sends a transport / countdown / lock command to the director. Returns false
    /// when this device is not an operator or the send failed.
    @discardableResult
    func sendCommand(_ verb: ShowLiveCommandVerb, value: Double? = nil) -> Bool {
        guard role == .remote else { return false }
        return send(ShowLiveEnvelope(
            kind: .command, command: ShowLiveCommand(verb: verb, value: value)
        ))
    }

    /// Pushes current program to connected operators. No-op when not director.
    func broadcastSnapshot(_ snap: ShowLiveSnapshot) {
        guard role == .director else { return }
        guard snapshot != snap else { return }
        snapshot = snap
        directorDeviceName = snap.directorName
        _ = send(ShowLiveEnvelope(
            kind: .state, itemKind: nil, itemId: nil, snapshot: snap
        ))
    }

    /// Re-sends the last snapshot so a newly connected operator is not blank.
    func pushSnapshotToPeers() {
        guard role == .director, let snapshot else { return }
        _ = send(ShowLiveEnvelope(
            kind: .state, itemKind: nil, itemId: nil, snapshot: snapshot
        ))
    }

    /// Drops the session (Show closed or HDMI lost).
    func leave() {
        openingShowId = nil
        foundDirector = false
        tearDownSession()
    }

    func notifyChanged(programChanged: Bool = true) {
        NotificationCenter.default.post(
            name: Self.didChangeNotification,
            object: self,
            userInfo: [Self.programChangedKey: programChanged]
        )
    }

    // MARK: - CloudKit identity

    /// Resolves the iCloud user hash that scopes peers to one account, and
    /// reloads the account key.
    ///
    /// Leaves `userHash` nil where CloudKit is unreachable, and `userKey` nil
    /// while the Keychain is unavailable — advertising, browsing, and
    /// invitations all require both, so Show Live simply stays off and tries
    /// again on the next sync. The key is re-read each time so phones that made
    /// a secret at the same moment settle on the one iCloud Keychain keeps.
    func refreshCloudKitUser(then completion: (() -> Void)? = nil) {
        userKey = ShowLiveAccountSecret.loadOrCreate().map {
            ShowLiveInviteProof.key(forAccountSecret: $0)
        }
        if userHash != nil {
            completion?()
            return
        }
        guard let container = CloudKitAvailability.container() else {
            completion?()
            return
        }
        Task { @MainActor in
            do {
                let recordID = try await container.userRecordID()
                self.userHash = ShowLiveRouting.hashedUserId(recordID.recordName)
            } catch {
                self.logger.error(
                    "Show live user id failed: \(error.localizedDescription)"
                )
            }
            completion?()
        }
    }

    // MARK: - Session helpers

    func ensureSession() -> MCSession {
        if let session { return session }
        let next = MCSession(
            peer: peerID,
            securityIdentity: nil,
            encryptionPreference: .required
        )
        next.delegate = self
        session = next
        return next
    }

    /// Sends to peers that passed the mutual check only, sealed per peer.
    func send(_ envelope: ShowLiveEnvelope) -> Bool {
        sendToVerifiedPeers(envelope)
    }

    func tearDownSession() {
        stopElection()
        stopAdvertising()
        stopBrowsing()
        session?.disconnect()
        session = nil
        peerHandshakes = [:]
        snapshot = nil
        directorDeviceName = nil
        if role != .none {
            role = .none
            notifyChanged()
        } else {
            role = .none
        }
    }

    func continueSync(showId: UUID) {
        let hasDisplay = ExternalDisplayManager.shared.isConnected
        switch role {
        case .remote:
            return
        case .director:
            if ShowLiveRouting.shouldAdvertise(
                hasExternalDisplay: hasDisplay,
                isShowOpen: true,
                isRemoteOperator: false
            ) {
                startAdvertising(showId: showId)
            } else {
                tearDownSession()
                openingShowId = showId
                startBrowsing(showId: showId)
            }
        case .none:
            startBrowsing(showId: showId)
            if hasDisplay, !foundDirector {
                scheduleElection(showId: showId)
            }
        }
    }

    func applyReceived(_ envelope: ShowLiveEnvelope, from peer: MCPeerID) {
        switch envelope.kind {
        case .select:
            guard role == .director, let kind = envelope.itemKind else { return }
            var info: [String: String] = [Self.selectKindKey: kind.rawValue]
            if let itemId = envelope.itemId {
                info[Self.selectItemIdKey] = itemId
            }
            NotificationCenter.default.post(
                name: Self.incomingSelectNotification, object: self, userInfo: info
            )
        case .state:
            guard role == .remote, let snap = envelope.snapshot else { return }
            let programChanged = !snap.isSameProgram(as: snapshot)
            snapshot = snap
            directorDeviceName = snap.directorName
            notifyChanged(programChanged: programChanged)
        case .command:
            guard role == .director, let command = envelope.command else { return }
            NotificationCenter.default.post(
                name: Self.incomingCommandNotification,
                object: self,
                userInfo: [Self.commandKey: command]
            )
        }
        _ = peer
    }

    func handlePeerState(_ state: MCSessionState, peer: MCPeerID) {
        switch state {
        case .connected:
            // Nothing is trusted until the peer passes the mutual check.
            beginHandshake(with: peer)
        case .notConnected:
            handlePeerDrop(peer)
        default:
            break
        }
    }

    /// Runs once `peer` proved it holds the account key.
    func peerDidAuthenticate(_ peer: MCPeerID, peerRole: ShowLivePeerRole) {
        if role == .none, foundDirector, peerRole == .director {
            // Connecting always ends discovery; taking the operator role is
            // the separate question of whether the director will act.
            if ShowLiveRouting.shouldBecomeRemoteOperator(
                foundDirector: foundDirector
            ) {
                role = .remote
                directorDeviceName = peer.displayName
            }
            stopBrowsing()
            stopElection()
            notifyChanged()
        } else if role == .director, peerRole == .joiner {
            pushSnapshotToPeers()
            notifyChanged()
        }
    }

    private func handlePeerDrop(_ peer: MCPeerID) {
        let droppedDirector = peerHandshakes[peer]?.peerRole == .director
        peerHandshakes[peer] = nil
        let stillHavePeers = !(session?.connectedPeers.isEmpty ?? true)
        if role == .remote, droppedDirector {
            role = .none
            snapshot = nil
            directorDeviceName = nil
            notifyChanged()
            if let showId = openingShowId {
                foundDirector = false
                startBrowsing(showId: showId)
                if ExternalDisplayManager.shared.isConnected {
                    scheduleElection(showId: showId)
                }
            }
        } else if role == .director, !stillHavePeers {
            notifyChanged()
        }
        _ = peer
    }
}
