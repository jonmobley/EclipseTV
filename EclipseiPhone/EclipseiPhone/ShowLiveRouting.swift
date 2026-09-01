//
//  ShowLiveRouting.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CryptoKit
import Foundation

/// Pure decisions for the live-show remote. Kept off Multipeer so tests do not
/// need a LAN or an `MCSession`.
enum ShowLiveRouting {
    /// Browse this long before a device with HDMI/AirPlay advertises as director.
    static let electionWindow: TimeInterval = 0.4

    /// HDMI/AirPlay device with an open Show advertises. Practice (no display)
    /// and operators never do.
    static func shouldAdvertise(
        hasExternalDisplay: Bool,
        isShowOpen: Bool,
        isRemoteOperator: Bool
    ) -> Bool {
        hasExternalDisplay && isShowOpen && !isRemoteOperator
    }

    /// Auto-join only when the advertised Show and CloudKit user both match.
    static func canAutoJoin(
        advertisedShowId: UUID?,
        advertisedUserHash: String?,
        localShowId: UUID?,
        localUserHash: String?
    ) -> Bool {
        guard let advertisedShowId, let advertisedUserHash,
              let localShowId, let localUserHash,
              !advertisedUserHash.isEmpty, !localUserHash.isEmpty
        else { return false }
        return advertisedShowId == localShowId
            && advertisedUserHash == localUserHash
    }

    /// After the browse window, advertise only when nobody else is director.
    static func shouldBecomeDirectorAfterElection(
        foundDirector: Bool,
        hasExternalDisplay: Bool,
        isRemoteOperator: Bool
    ) -> Bool {
        !foundDirector && !isRemoteOperator && hasExternalDisplay
    }

    /// Operator taps command the director instead of presenting locally.
    static func shouldCommandDirector(isRemoteOperator: Bool) -> Bool {
        isRemoteOperator
    }

    /// Short hash for discovery info (Multipeer discoveryInfo is tiny).
    static func hashedUserId(_ recordName: String) -> String {
        let digest = SHA256.hash(data: Data(recordName.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    /// Truncates a device name so it fits discovery info.
    static func shortDeviceName(_ name: String, maxLength: Int = 24) -> String {
        if name.count <= maxLength { return name }
        return String(name.prefix(maxLength))
    }
}
