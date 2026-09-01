//
//  AirPlayOverlayPark.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Dual-path park: EclipseTV goes black while AirPlay owns an overlay the TV cannot show.
enum AirPlayOverlayPark {

    /// Whether the phone still wants linked TVs parked (reconnect re-sends black).
    @MainActor
    private(set) static var shouldBeParked = false

    /// Park only when EclipseTV is linked and AirPlay / HDMI is actually connected.
    static func shouldParkTV(
        eclipseTVOnline: Bool,
        airPlayConnected: Bool
    ) -> Bool {
        eclipseTVOnline && airPlayConnected
    }

    /// Parks every synced TV and remembers the desire so reconnect can re-send.
    @MainActor
    @discardableResult
    static func park(
        using connectionManager: iPhoneConnectionManager
    ) -> Bool {
        shouldBeParked = true
        return connectionManager.sendSetIdleMode(black: true)
    }

    /// Clears park on every synced TV and forgets the desire.
    @MainActor
    @discardableResult
    static func clear(
        using connectionManager: iPhoneConnectionManager
    ) -> Bool {
        let wasParked = shouldBeParked
        shouldBeParked = false
        guard wasParked else { return false }
        return connectionManager.sendSetIdleMode(black: false)
    }

    /// Drops the desire without sending (TV already unparked via `playRequest`).
    @MainActor
    static func noteUnparkedByPlayRequest() {
        shouldBeParked = false
    }

    /// Re-sends black after Multipeer reconnect when AirPlay overlay is still live.
    @MainActor
    static func reparkIfNeeded(
        using connectionManager: iPhoneConnectionManager,
        eclipseTVOnline: Bool,
        airPlayConnected: Bool
    ) {
        guard shouldBeParked,
              shouldParkTV(
                eclipseTVOnline: eclipseTVOnline,
                airPlayConnected: airPlayConnected
              ) else { return }
        _ = connectionManager.sendSetIdleMode(black: true)
    }
}
