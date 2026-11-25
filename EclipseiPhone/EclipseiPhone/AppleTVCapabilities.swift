//
//  AppleTVCapabilities.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import MultipeerConnectivity

/// Remembers which features each connected Apple TV said it understands.
///
/// A TV lists its features in its library manifest (`capabilities`). Older TV
/// builds list nothing, so the phone keeps sending them today's messages (for a
/// slideshow: one photo at a time). Forgotten when the TV disconnects.
///
/// Thread Safety: Main actor only.
@MainActor
final class AppleTVCapabilities {

    // MARK: - Properties

    /// Shared registry used by the connection manager.
    static let shared = AppleTVCapabilities()

    private var byPeer: [MCPeerID: Set<String>] = [:]

    // MARK: - Public Interface

    /// Records what a TV reported in its manifest.
    /// - Parameters:
    ///   - capabilities: The manifest's list; nil from older TVs (stored as none).
    ///   - peer: The TV that sent it.
    func record(_ capabilities: [String]?, for peer: MCPeerID) {
        byPeer[peer] = Set(capabilities ?? [])
    }

    /// Forgets a TV (it disconnected).
    /// - Parameter peer: The TV.
    func forget(_ peer: MCPeerID) {
        byPeer[peer] = nil
    }

    /// Whether `peer` can play a whole slideshow by itself.
    /// - Parameter peer: The TV; nil (no TV) is never capable.
    /// - Returns: `true` only when that TV listed `EclipseShareCapability.slideshow`.
    func supportsSlideshow(_ peer: MCPeerID?) -> Bool {
        guard let peer, let capabilities = byPeer[peer] else { return false }
        return EclipseShareCapability.supportsSlideshow(Array(capabilities))
    }
}
