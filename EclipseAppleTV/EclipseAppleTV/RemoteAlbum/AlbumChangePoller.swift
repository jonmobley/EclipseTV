//
//  AlbumChangePoller.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Asks the caller to re-sync the configured account's albums every few minutes while
/// the app is active.
///
/// This replaced a Supabase Realtime WebSocket tied to the album host's database, so
/// installed TVs depend only on the manifest address in `AlbumConfig` (a domain we
/// control). The manifest sync (`RemoteAlbumSync`) stays the source of truth and is
/// idempotent, so an extra tick is cheap. Safe to `start`/`stop` repeatedly.
@MainActor
final class AlbumChangePoller {

    /// Invoked on the main actor each time a re-sync is due.
    var onChange: (() -> Void)?

    /// Time between re-syncs while the app is active.
    static let interval: TimeInterval = 5 * 60

    private let logger = Logger(subsystem: "com.eclipsetv.app", category: "AlbumChangePoller")
    private var timer: Timer?
    private var currentCode: String?

    /// Starts polling for `code`. No-op if already polling the same code or if `code`
    /// is malformed.
    func start(code: String) {
        let normalized = AlbumConfig.normalize(code)
        guard AlbumConfig.isValidCode(normalized) else { return }
        guard normalized != currentCode || timer == nil else { return }
        stop()
        currentCode = normalized
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.onChange?() }
        }
        logger.info("Album re-sync every \(Int(Self.interval), privacy: .public)s")
    }

    /// Stops polling (backgrounded, or albums removed).
    func stop() {
        timer?.invalidate()
        timer = nil
        currentCode = nil
    }
}
