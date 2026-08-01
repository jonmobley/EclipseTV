//
//  CloudKitSaveFailurePolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// What the sync engine should do after a failed record save.
enum CloudKitSaveFailureAction: Equatable {
    /// Transient — `CKSyncEngine` retries on its own; take no app-side action.
    case retryHandledByEngine
    /// Apply the server record, then re-queue our local version.
    case mergeAndRequeue
    /// The custom zone is gone; recreate it and re-enqueue local content.
    case recreateZone
    /// Server no longer has this record; drop the pending change so the queue
    /// cannot wedge.
    case dropPendingChange
    /// iCloud storage is full; park the record until space frees.
    case holdForQuota
    /// No recovery path; log and leave state alone.
    case logOnly
}

/// Pure mapping from `CKError.Code` to a recovery action.
///
/// Kept free of `CKError` construction so unit tests can cover every branch
/// without fabricating CloudKit error objects.
enum CloudKitSaveFailurePolicy {

    /// Recovery action for a failed CloudKit record save.
    ///
    /// Retryables (`networkUnavailable`, `networkFailure`, `serviceUnavailable`,
    /// `zoneBusy`, `requestRateLimited`, `notAuthenticated`, `operationCancelled`)
    /// deliberately map to `.retryHandledByEngine` — `CKSyncEngine` requeues those
    /// itself, and re-scheduling from here would only amplify traffic.
    static func action(for code: CKError.Code) -> CloudKitSaveFailureAction {
        switch code {
        case .quotaExceeded:
            return .holdForQuota
        case .serverRecordChanged:
            return .mergeAndRequeue
        case .zoneNotFound:
            return .recreateZone
        case .unknownItem:
            return .dropPendingChange
        case .networkUnavailable,
             .networkFailure,
             .serviceUnavailable,
             .zoneBusy,
             .requestRateLimited,
             .notAuthenticated,
             .operationCancelled:
            return .retryHandledByEngine
        default:
            return .logOnly
        }
    }
}
