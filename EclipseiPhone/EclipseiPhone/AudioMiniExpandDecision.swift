//
//  AudioMiniExpandDecision.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Whether a freshly started ambient session should reveal the mini player card
/// or leave the Music circle standing alone.
///
/// Picking a track in the Music picker is the one moment the user has just said
/// what they want to hear, so the card comes up with the answer instead of
/// asking for a second tap on the circle. Playback that starts anywhere else —
/// background music armed at launch, the embedded Music page, the lock screen —
/// leaves the chrome exactly as the user left it.
enum AudioMiniExpandDecision {

    /// Decides whether to expand the card as playback begins.
    ///
    /// - Parameters:
    ///   - sessionJustStarted: A session exists now and did not a moment ago.
    ///   - startedFromPicker: The Music picker sheet was on screen when it started.
    ///   - usesDrawerChrome: Regular width, where Music lives in the drawer and
    ///     the card never appears.
    /// - Returns: True when the card should expand.
    static func shouldExpandCard(
        sessionJustStarted: Bool,
        startedFromPicker: Bool,
        usesDrawerChrome: Bool
    ) -> Bool {
        sessionJustStarted && startedFromPicker && !usesDrawerChrome
    }
}
