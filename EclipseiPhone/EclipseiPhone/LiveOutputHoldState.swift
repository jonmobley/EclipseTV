//
//  LiveOutputHoldState.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Which live-output controls are on, and the rules between them.
///
/// Mirrors the Mac: Freeze and Lock are never on together, and neither are
/// Blackout and White. Blackout and White are both "blank" screens, so a blank
/// also ends Freeze (there is no picture left to hold, and the panic button wins).
///
/// Pure value type, no UIKit: the grid owns one and applies what changed.
/// Thread safety: main thread only (it is plain value state).
struct LiveOutputHoldState: Equatable {

    // MARK: Properties

    /// The audience screen holds a still picture while the phone keeps browsing.
    private(set) var isFrozen = false
    /// The audience screen is solid white.
    private(set) var isWhite = false
    /// Lock is on (tile taps preview on the phone instead of going live).
    private(set) var isLocked = false
    /// Blackout is on (solid black).
    private(set) var isBlack = false

    /// Either blank colour is on.
    var isBlank: Bool { isWhite || isBlack }

    // MARK: Rules

    /// Whether Freeze can be turned on: a blank screen has nothing to hold.
    var canFreeze: Bool { !isBlank }

    /// Flips Freeze. Turning it on turns Lock off; it never turns on over a blank.
    /// - Returns: True when Freeze is now on.
    @discardableResult
    mutating func toggleFreeze() -> Bool {
        if isFrozen {
            isFrozen = false
        } else if canFreeze {
            isFrozen = true
            isLocked = false
        }
        return isFrozen
    }

    /// Flips White. Turning it on turns Blackout and Freeze off.
    /// - Returns: True when White is now on.
    @discardableResult
    mutating func toggleWhite() -> Bool {
        isWhite.toggle()
        if isWhite {
            isBlack = false
            isFrozen = false
        }
        return isWhite
    }

    /// Records Lock as set by the grid. Turning it on turns Freeze off.
    mutating func setLocked(_ locked: Bool) {
        isLocked = locked
        if locked { isFrozen = false }
    }

    /// Records Blackout as set by the grid. Turning it on turns White and Freeze off.
    mutating func setBlack(_ black: Bool) {
        isBlack = black
        if black {
            isWhite = false
            isFrozen = false
        }
    }

    /// Clears Freeze, e.g. when the external screen goes away.
    mutating func clearFreeze() {
        isFrozen = false
    }

    /// Clears White, e.g. when the external screen goes away.
    mutating func clearWhite() {
        isWhite = false
    }
}
