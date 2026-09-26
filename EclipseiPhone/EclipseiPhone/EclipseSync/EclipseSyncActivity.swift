//
//  EclipseSyncActivity.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Remembers when CloudKit last finished a fetch or a send, for the Settings row.
///
/// `CKSyncEngine` has no "last synced" of its own; this is stamped from the delegate
/// whenever record-zone changes arrive or are acknowledged, on either database.
@MainActor
final class EclipseSyncActivity {

    static let shared = EclipseSyncActivity()

    /// Posted after `noteSyncCompleted`.
    nonisolated static let didChangeNotification =
        Notification.Name("EclipseSyncActivity.didChange")

    private(set) var lastSyncedAt: Date?

    private let defaults: UserDefaults
    private let key: String

    init(
        defaults: UserDefaults = .standard,
        key: String = "EclipseTV.cloudKit.lastSyncedAt"
    ) {
        self.defaults = defaults
        self.key = key
        lastSyncedAt = defaults.object(forKey: key) as? Date
    }

    /// Records a completed round-trip with CloudKit.
    func noteSyncCompleted(at date: Date = Date()) {
        lastSyncedAt = date
        defaults.set(date, forKey: key)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}

// MARK: - Settings copy

/// One-line Eclipse Sync status for Settings, e.g. "On · Synced 2 minutes ago".
enum EclipseSyncStatusSummary {

    /// Secondary text for the Settings row.
    static func text(
        pauseReason: SyncPauseReason?,
        lastSyncedAt: Date?,
        now: Date = Date()
    ) -> String {
        if let pauseReason {
            return "Paused · \(shortReason(pauseReason))"
        }
        guard let lastSyncedAt else { return "On" }
        return "On · Synced \(relative(lastSyncedAt, now: now))"
    }

    /// Short cause suitable for a table row; the banner keeps the full sentence.
    static func shortReason(_ reason: SyncPauseReason) -> String {
        switch reason {
        case .noAccount: return "Not signed in to iCloud"
        case .quotaExceeded: return "iCloud storage is full"
        case .temporarilyUnavailable: return "iCloud unavailable"
        }
    }

    /// "just now" inside a minute, otherwise the system relative phrase.
    static func relative(_ date: Date, now: Date) -> String {
        if now.timeIntervalSince(date) < 60 { return "just now" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: now)
    }
}
