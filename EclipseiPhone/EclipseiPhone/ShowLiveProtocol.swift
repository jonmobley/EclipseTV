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
    enum Kind: String, Codable {
        case select
        case state
    }
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
}

/// JSON blob sent over the `eclipse-live` Multipeer session.
struct ShowLiveEnvelope: Codable, Equatable {
    var kind: ShowLiveProtocol.Kind
    var itemKind: ShowLiveItemKind?
    var itemId: String?
    var snapshot: ShowLiveSnapshot?
}
