//
//  ShowLiveSession.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
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

    func notifyChanged() {
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    // MARK: - CloudKit identity

    func refreshCloudKitUser(then completion: (() -> Void)? = nil) {
        if userHash != nil {
            completion?()
            return
        }
        Task { @MainActor in
            do {
                let container = CKContainer(
                    identifier: CloudKitSchema.containerIdentifier
                )
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

    func send(_ envelope: ShowLiveEnvelope) -> Bool {
        guard let session, !session.connectedPeers.isEmpty,
              let data = try? JSONEncoder().encode(envelope)
        else { return false }
        do {
            try session.send(data, toPeers: session.connectedPeers, with: .reliable)
            return true
        } catch {
            logger.error("Show live send failed: \(error.localizedDescription)")
            return false
        }
    }

    func tearDownSession() {
        stopElection()
        stopAdvertising()
        stopBrowsing()
        session?.disconnect()
        session = nil
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
            snapshot = snap
            directorDeviceName = snap.directorName
            notifyChanged()
        }
        _ = peer
    }

    func handlePeerState(_ state: MCSessionState, peer: MCPeerID) {
        switch state {
        case .connected:
            if role == .none, foundDirector {
                role = .remote
                directorDeviceName = peer.displayName
                stopBrowsing()
                stopElection()
                notifyChanged()
            } else if role == .director {
                pushSnapshotToPeers()
                notifyChanged()
            }
        case .notConnected:
            handlePeerDrop(peer)
        default:
            break
        }
    }

    private func handlePeerDrop(_ peer: MCPeerID) {
        let stillHavePeers = !(session?.connectedPeers.isEmpty ?? true)
        if role == .remote {
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
            guard let envelope = try? JSONDecoder().decode(
                ShowLiveEnvelope.self, from: data
            ) else { return }
            self.applyReceived(envelope, from: peerID)
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
