//
//  ShowLiveProtocol.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Wire contract for the iOS↔iOS live-show remote (`eclipse-live`).
///
/// Not `EclipseShareProtocol`: that service is phone↔Apple TV library mirroring.
enum ShowLiveProtocol {
    /// Multipeer service type (Bonjour names are capped at 15 characters).
    static let serviceType = "eclipse-live"

    /// Discovery-info key for the advertised Show UUID.
    static let discoveryShowId = "s"
    /// Discovery-info key for the hashed CloudKit user id.
    static let discoveryUserHash = "u"
    /// Discovery-info key for a short director device name.
    static let discoveryDeviceName = "n"

    /// Discriminator for a JSON envelope on `MCSession.send`.
    ///
    /// A peer on an older build fails to decode an unknown kind and drops the
    /// message, so adding a case is backward compatible.
    enum Kind: String, Codable {
        case select
        case state
        case command
    }
}

/// Operator verbs that adjust the director's program without changing what is live.
enum ShowLiveCommandVerb: String, Codable, Equatable {
    /// Play / pause the director's library video.
    case videoToggle
    /// Relative skip; `value` is seconds (negative rewinds).
    case videoSkip
    /// Absolute seek; `value` is seconds.
    case videoSeek
    /// Pause the live countdown if running, otherwise start it.
    case countdownToggleRunning
    /// Reset the live countdown to its duration.
    case countdownReset
    /// Set the live countdown duration; `value` is whole seconds.
    case countdownSetDuration
    /// Flip the director's live-output lock.
    case lockToggle
}

/// One operator command; `value` is only read for verbs that document it.
struct ShowLiveCommand: Codable, Equatable {
    var verb: ShowLiveCommandVerb
    var value: Double?
}

/// Director library-video transport, mirrored so the operator scrubber is live.
struct ShowLiveVideoState: Codable, Equatable {
    var isPlaying: Bool
    /// Whole seconds: sub-second ticks would otherwise send four snapshots a second.
    var currentTime: Int
    var duration: Int
}

/// Director countdown clock, mirrored so the operator hero shows the real time.
struct ShowLiveCountdownState: Codable, Equatable {
    var remaining: Int
    var duration: Int
    var running: Bool
}

/// What the operator asked the director to put on program.
enum ShowLiveItemKind: String, Codable, Equatable {
    case media
    case web
    case pdf
    case camera
    case countdown
    case slideshow
    case logo
    case screensaver
    case livePoll
    case black
}

/// Compact invitation payload so a stale advertisement cannot bind the wrong Show.
struct ShowLiveInvitation: Codable, Equatable {
    var showId: UUID
    var userHash: String

    enum CodingKeys: String, CodingKey {
        case showId = "s"
        case userHash = "u"
    }
}

/// Director program state mirrored to operators. No media bytes — both devices
/// already have the Show via CloudKit.
struct ShowLiveSnapshot: Codable, Equatable {
    var showId: UUID
    var liveItemId: String?
    var liveKind: ShowLiveItemKind?
    var isBlackout: Bool
    var isLocked: Bool
    var directorName: String
    /// Present only while library video is live. Absent from legacy peers.
    var video: ShowLiveVideoState?
    /// Present only while a countdown is live. Absent from legacy peers.
    var countdown: ShowLiveCountdownState?

    init(
        showId: UUID,
        liveItemId: String?,
        liveKind: ShowLiveItemKind?,
        isBlackout: Bool,
        isLocked: Bool,
        directorName: String,
        video: ShowLiveVideoState? = nil,
        countdown: ShowLiveCountdownState? = nil
    ) {
        self.showId = showId
        self.liveItemId = liveItemId
        self.liveKind = liveKind
        self.isBlackout = isBlackout
        self.isLocked = isLocked
        self.directorName = directorName
        self.video = video
        self.countdown = countdown
    }

    /// True when only transport / clock ticks differ from `other`, so an operator
    /// can refresh the hero without rebuilding the grid.
    func isSameProgram(as other: ShowLiveSnapshot?) -> Bool {
        guard let other else { return false }
        return showId == other.showId
            && liveItemId == other.liveItemId
            && liveKind == other.liveKind
            && isBlackout == other.isBlackout
            && isLocked == other.isLocked
            && directorName == other.directorName
    }
}

/// JSON blob sent over the `eclipse-live` Multipeer session.
struct ShowLiveEnvelope: Codable, Equatable {
    var kind: ShowLiveProtocol.Kind
    var itemKind: ShowLiveItemKind?
    var itemId: String?
    var snapshot: ShowLiveSnapshot?
    /// Set only for `kind == .command`. Absent from legacy peers.
    var command: ShowLiveCommand?

    init(
        kind: ShowLiveProtocol.Kind,
        itemKind: ShowLiveItemKind? = nil,
        itemId: String? = nil,
        snapshot: ShowLiveSnapshot? = nil,
        command: ShowLiveCommand? = nil
    ) {
        self.kind = kind
        self.itemKind = itemKind
        self.itemId = itemId
        self.snapshot = snapshot
        self.command = command
    }
}
