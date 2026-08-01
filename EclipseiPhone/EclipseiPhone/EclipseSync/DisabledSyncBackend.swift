//
//  DisabledSyncBackend.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Stand-in backend for builds that cannot reach CloudKit.
///
/// `CKContainer(identifier:)` *traps* rather than failing when the identifier is
/// missing from the app's entitlements, so constructing the CloudKit backend in an
/// unentitled build takes the whole process down at launch — including the XCTest
/// host, which is signed without the iCloud capability. Sync reports itself paused
/// here instead, so the rest of the app runs untouched.
@MainActor
final class DisabledSyncBackend: SyncBackend {

    /// Why sync is unavailable, surfaced through `pauseReason`.
    private let reason: String

    private let logger = Logger(
        subsystem: "com.eclipseapp.ios",
        category: "DisabledSync"
    )

    init(reason: String) {
        self.reason = reason
    }

    var isAccountAvailable: Bool { false }

    var pauseReason: SyncPauseReason? { .temporarilyUnavailable(reason) }

    func start() {
        logger.info("Eclipse Sync disabled: \(self.reason, privacy: .public)")
    }

    func retryPendingWork() {}

    func scheduleShowSave(id: UUID) {}

    func scheduleShowDelete(id: UUID) {}

    func scheduleCaptureSave(id: String) {}

    func scheduleCaptureDelete(id: String) {}

    func schedulePDFSave(id: UUID) {}

    func schedulePDFDelete(id: UUID) {}

    func downloadAsset(
        id: String,
        progress: (@Sendable (Double) -> Void)?,
        completion: @escaping @MainActor (Result<URL, Error>) -> Void
    ) {
        completion(.failure(SyncUnavailableError.disabled(reason)))
    }

    func removeLocalDownload(id: String) {}

    func presentShareUI(forShowId id: UUID, from presenter: AnyObject) {}
}

/// Failure returned by `DisabledSyncBackend` for operations that need a transport.
enum SyncUnavailableError: LocalizedError {
    case disabled(String)

    var errorDescription: String? {
        switch self {
        case .disabled(let reason):
            return reason
        }
    }
}
