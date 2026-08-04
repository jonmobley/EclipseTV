//
//  EclipseSyncController.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import UIKit

/// App-wide entry point for Eclipse Sync (CloudKit today; swappable via `SyncBackend`).
@MainActor
final class EclipseSyncController {

    static let shared = EclipseSyncController()

    /// Posted when account / quota pause reason changes.
    nonisolated static let statusDidChangeNotification =
        Notification.Name("EclipseSyncController.statusDidChange")

    /// Active transport. Replace for tests or a future SaaS backend.
    private(set) var backend: SyncBackend

    /// When true, local store mutations must not schedule uploads (remote apply in progress).
    var isApplyingRemote = false

    private var statusObserver: NSObjectProtocol?

    private init() {
        backend = Self.makeDefaultBackend()
    }

    /// CloudKit where it can run, a disabled stand-in where it can't.
    ///
    /// The XCTest host is signed without the iCloud capability, and
    /// `CKContainer(identifier:)` traps on an identifier that isn't in the app's
    /// entitlements — so building the CloudKit backend there killed the process
    /// before any test could run.
    private static func makeDefaultBackend() -> SyncBackend {
        guard !isRunningUnitTests else {
            return DisabledSyncBackend(
                reason: "Eclipse Sync is off in the test host."
            )
        }
        return CloudKitSyncEngine()
    }

    private static var isRunningUnitTests: Bool {
        ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    }

    /// Boots the sync backend. Call once from `AppDelegate`.
    func start() {
        backend.start()
        if statusObserver == nil {
            statusObserver = NotificationCenter.default.addObserver(
                forName: CloudKitAccountMonitor.didChangeNotification,
                object: nil,
                queue: .main
            ) { _ in
                NotificationCenter.default.post(
                    name: Self.statusDidChangeNotification,
                    object: nil
                )
            }
            NotificationCenter.default.addObserver(
                forName: UIApplication.willEnterForegroundNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                Task { @MainActor in
                    await self?.refreshAccount()
                    self?.backend.retryPendingWork()
                }
            }
        }
    }

    /// Re-checks iCloud account status (e.g. after returning from Settings).
    func refreshAccount() async {
        if let engine = backend as? CloudKitSyncEngine {
            await engine.account.refresh()
        }
    }

    /// Injects a backend (unit tests / future SaaS).
    func install(backend: SyncBackend) {
        self.backend = backend
        backend.start()
    }

    var pauseReason: SyncPauseReason? { backend.pauseReason }

    var isAccountAvailable: Bool { backend.isAccountAvailable }

    /// Banner copy when sync is paused, or nil when healthy / not yet evaluated.
    var statusBannerText: String? {
        pauseReason?.userMessage
    }

    /// Applies a server tombstone to whichever local store owns `recordName`.
    ///
    /// Shows and PDFs both use a bare UUID as their record name, so the owner has to be
    /// resolved by asking the stores; deletions carry no record type. Runs with
    /// `isApplyingRemote` set so the local delete does not echo back as an upload.
    func applyRemoteDeletion(recordName: String) {
        let wasApplying = isApplyingRemote
        isApplyingRemote = true
        defer { isApplyingRemote = wasApplying }

        if let uuid = UUID(uuidString: recordName) {
            if LocalAlbumStore.shared.album(id: uuid) != nil {
                LocalAlbumStore.shared.delete(id: uuid)
                return
            }
            if PDFStore.shared.documents.contains(where: { $0.id == uuid }) {
                PDFStore.shared.remove(id: uuid)
                return
            }
        }
        CaptureStore.shared.purge(id: recordName)
    }
}
