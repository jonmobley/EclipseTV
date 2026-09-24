//
//  SyncBackendFetchChangesTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

@MainActor
struct SyncBackendFetchChangesTests {

    @Test func disabledBackendFetchChangesIsANoOp() {
        let backend = DisabledSyncBackend(reason: "test")
        backend.fetchChangesNow()
        #expect(backend.isAccountAvailable == false)
    }
}
