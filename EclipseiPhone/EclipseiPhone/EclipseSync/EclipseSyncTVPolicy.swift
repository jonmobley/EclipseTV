//
//  EclipseSyncTVPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Documents the Phase 1 decision that Apple TV does **not** participate in CloudKit.
///
/// Reasons (see project rule `appletv-storage` and the EclipseSync plan):
/// - The TV's on-disk strategy is locked; enabling CloudKit there needs an explicit ask.
/// - In-app captures must never be sent to an Apple TV.
/// - The TV already receives imported media over Multipeer from the phone.
///
/// When CloudKit-on-TV is approved later, add a tvOS target entitlement and a
/// read-only `CKSyncEngine` that never writes captures into Multipeer uploads.
enum EclipseSyncTVPolicy {
    /// Phase 1: iPhone (and future Mac) only.
    static let appleTVParticipates = false
}
