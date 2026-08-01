//
//  CloudKitAccountMonitor.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation
import os.log

/// Tracks iCloud account availability and surfaceable sync pause reasons.
@MainActor
final class CloudKitAccountMonitor {

    static let didChangeNotification = Notification.Name("CloudKitAccountMonitor.didChange")

    private(set) var accountStatus: CKAccountStatus = .couldNotDetermine
    /// Nil until the first `refresh()` resolves, so the header stays quiet at launch
    /// instead of flashing "Sign in to iCloud" before we know the answer.
    private(set) var pauseReason: SyncPauseReason?

    private let container: CKContainer
    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "CloudKitAccount"
    )
    private var observer: NSObjectProtocol?

    init(container: CKContainer) {
        self.container = container
    }

    /// Begins observing account changes and refreshes status immediately.
    func start() {
        if observer == nil {
            observer = NotificationCenter.default.addObserver(
                forName: Notification.Name.CKAccountChanged,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refresh()
                }
            }
        }
        Task { await refresh() }
    }

    /// Re-fetches `CKAccountStatus` and updates `pauseReason`.
    func refresh() async {
        do {
            accountStatus = try await container.accountStatus()
        } catch {
            logger.error("accountStatus failed: \(error.localizedDescription)")
            accountStatus = .couldNotDetermine
        }
        // Keep a quota pause only while the account is still available; sign-out should
        // surface "sign in" instead of a stale storage-full banner.
        applyPauseReason(
            from: accountStatus,
            preservingQuota: pauseReason == .quotaExceeded
                && accountStatus == .available
        )
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Marks sync paused because iCloud storage is full.
    func noteQuotaExceeded() {
        pauseReason = .quotaExceeded
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    /// Clears a quota pause after the user frees space (next successful write also clears).
    func clearQuotaPause() {
        guard pauseReason == .quotaExceeded else { return }
        applyPauseReason(from: accountStatus, preservingQuota: false)
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }

    var isAccountAvailable: Bool {
        accountStatus == .available
    }

    /// Maps account status to a pause reason without inventing a "sign in" prompt for
    /// transient CloudKit unavailability.
    private func applyPauseReason(
        from status: CKAccountStatus,
        preservingQuota: Bool
    ) {
        if preservingQuota { return }
        switch status {
        case .available:
            pauseReason = nil
        case .noAccount, .restricted:
            pauseReason = .noAccount
        case .temporarilyUnavailable, .couldNotDetermine:
            pauseReason = .temporarilyUnavailable(
                "iCloud is temporarily unavailable. Eclipse Sync will resume automatically."
            )
        @unknown default:
            pauseReason = .temporarilyUnavailable(
                "iCloud is temporarily unavailable. Eclipse Sync will resume automatically."
            )
        }
    }
}
