//
//  CloudKitAvailabilityTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

/// The gate that keeps this whole suite runnable.
///
/// `CKContainer(identifier:)` traps on an identifier missing from the app's
/// entitlements, and the XCTest host is signed without the iCloud capability, so
/// an unguarded container takes the process down before any test reports. A
/// failure here means the next CloudKit call site added to launch will crash the
/// suite rather than fail a test.
struct CloudKitAvailabilityTests {

    @Test func cloudKitIsUnavailableInTheTestHost() {
        #expect(CloudKitAvailability.isAvailable == false)
        #expect(CloudKitAvailability.container() == nil)
    }

    /// `ShowLiveSession` must degrade rather than trap: no user hash means no
    /// advertising, browsing, or invitations, which is the correct offline state.
    @MainActor
    @Test func showLiveSessionLeavesUserHashNilWithoutCloudKit() {
        let session = ShowLiveSession.shared
        session.refreshCloudKitUser()
        #expect(session.userHash == nil)
    }

    /// Sync reports itself paused instead of building a CloudKit engine.
    @MainActor
    @Test func syncBackendIsDisabledInTheTestHost() {
        #expect(EclipseSyncController.shared.backend is DisabledSyncBackend)
    }
}
