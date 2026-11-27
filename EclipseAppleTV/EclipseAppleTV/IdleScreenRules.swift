//
//  IdleScreenRules.swift
//  EclipseTV
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// What the TV is doing, as far as the idle screen cares.
struct IdleScreenContext: Equatable {
    /// The library grid is up (nothing shown full screen).
    var isInGridMode: Bool
    /// The first-time "Link your iPhone" screen (with the pairing code) is up.
    var isShowingPairingScreen: Bool
    /// At least one iPhone has paired with this TV before.
    var hasPairedPhone: Bool
    /// The viewer is moving a tile with the remote.
    var isMoveMode: Bool
    /// A menu or alert is open on top.
    var isMenuOpen: Bool
    /// The phone has parked the TV on black (Blackout / AirPlay overlay).
    var isParked: Bool
    /// The viewer chose to browse the TV's own library from the idle screen.
    var isBrowsingLibrary: Bool
}

/// Rules for the calm idle screen (looping Eclipse video + a short hint).
///
/// The idle screen covers the library grid while the TV is ready and waiting for
/// the phone. It never hides first-time setup (the pairing code screen), a menu,
/// Move, or the phone's black park, and it steps aside once the viewer asks to
/// browse the TV's own library.
///
/// Thread Safety: Pure; safe from any thread.
enum IdleScreenRules {

    /// Seconds the hint stays before fading.
    static let hintVisibleSeconds: TimeInterval = 6

    /// Seconds the hint takes to fade in or out.
    static let hintFadeSeconds: TimeInterval = 0.6

    /// Seconds Select must be held on the idle screen to open Options.
    static let optionsHoldSeconds: TimeInterval = 0.8

    /// Main hint line.
    static let hintText = "Open Eclipse on your iPhone to show something here"

    /// Smaller second line: how to reach this TV's own library.
    static let browseHintText = "Press Select to browse this Apple TV"

    /// Whether the idle screen should be showing now.
    /// - Parameter context: The TV's current state.
    /// - Returns: `true` when the TV is ready and nothing else needs the screen.
    static func shouldShow(_ context: IdleScreenContext) -> Bool {
        context.isInGridMode
            && context.hasPairedPhone
            && !context.isShowingPairingScreen
            && !context.isMoveMode
            && !context.isMenuOpen
            && !context.isParked
            && !context.isBrowsingLibrary
    }

    /// What a remote press on the idle screen does.
    enum PressAction: Equatable {
        /// Bring the hint back (and keep idling).
        case showHint
        /// Leave the idle screen for the library grid.
        case browseLibrary
        /// Let the system have it (Menu leaves the app, like the root grid).
        case passThrough
    }

    /// Kinds of remote press the idle screen tells apart.
    enum Press: Equatable {
        case select
        case playPause
        case menu
        case arrow
        case other
    }

    /// Maps a remote press on the idle screen to what it does.
    /// - Parameter press: The press.
    /// - Returns: The action to take.
    static func action(for press: Press) -> PressAction {
        switch press {
        case .select, .playPause: return .browseLibrary
        case .menu: return .passThrough
        case .arrow, .other: return .showHint
        }
    }
}
