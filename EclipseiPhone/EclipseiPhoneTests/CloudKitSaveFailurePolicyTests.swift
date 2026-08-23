//
//  CloudKitSaveFailurePolicyTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Testing
@testable import EclipseiPhone

struct CloudKitSaveFailurePolicyTests {

    @Test func quotaExceededHoldsForQuota() {
        #expect(
            CloudKitSaveFailurePolicy.action(for: .quotaExceeded) == .holdForQuota
        )
    }

    @Test func serverRecordChangedMergesAndRequeues() {
        #expect(
            CloudKitSaveFailurePolicy.action(for: .serverRecordChanged)
                == .mergeAndRequeue
        )
    }

    @Test func zoneNotFoundRecreatesZone() {
        #expect(
            CloudKitSaveFailurePolicy.action(for: .zoneNotFound) == .recreateZone
        )
    }

    @Test func unknownItemDropsPendingChange() {
        #expect(
            CloudKitSaveFailurePolicy.action(for: .unknownItem)
                == .dropPendingChange
        )
    }

    @Test func serverRejectedRequestDropsPendingChange() {
        #expect(
            CloudKitSaveFailurePolicy.action(for: .serverRejectedRequest)
                == .dropPendingChange
        )
    }

    @Test func chainProtectionStripsParentAndRetries() {
        let message = """
            Error saving share to server: "Parent Record has no chain protection info"
            """
        #expect(
            CloudKitSaveFailurePolicy.action(
                for: .serverRejectedRequest,
                description: message
            ) == .stripShareParentAndRetry
        )
    }

    @Test func retryablesLeaveWorkToTheEngine() {
        let codes: [CKError.Code] = [
            .networkUnavailable,
            .networkFailure,
            .serviceUnavailable,
            .zoneBusy,
            .requestRateLimited,
            .notAuthenticated,
            .operationCancelled
        ]
        for code in codes {
            #expect(
                CloudKitSaveFailurePolicy.action(for: code)
                    == .retryHandledByEngine,
                "Expected retryHandledByEngine for \(code)"
            )
        }
    }

    @Test func unknownCodesLogOnly() {
        #expect(CloudKitSaveFailurePolicy.action(for: .internalError) == .logOnly)
        #expect(
            CloudKitSaveFailurePolicy.action(for: .invalidArguments) == .logOnly
        )
    }
}
