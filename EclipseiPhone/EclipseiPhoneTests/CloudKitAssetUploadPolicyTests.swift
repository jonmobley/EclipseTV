//
//  CloudKitAssetUploadPolicyTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct CloudKitAssetUploadPolicyTests {

    private let url = URL(fileURLWithPath: "/tmp/eclipse-test-asset.mov")

    @Test func pendingUploadCarriesTheFile() {
        #expect(CloudKitAssetUploadPolicy.assetURL(url, state: .pendingUpload) == url)
    }

    /// The whole point: a re-enqueued `.synced` capture must not re-send its bytes.
    @Test func syncedSavesMetadataOnly() {
        #expect(CloudKitAssetUploadPolicy.assetURL(url, state: .synced) == nil)
    }

    @Test func statesWithoutPendingBytesSendNoAsset() {
        for state in [
            CaptureSyncState.synced,
            .remoteOnly,
            .downloading,
            .localOnly
        ] {
            #expect(CloudKitAssetUploadPolicy.assetURL(url, state: state) == nil)
        }
    }

    // MARK: - PDFs

    private let pdfURL = URL(fileURLWithPath: "/tmp/eclipse-test-asset.pdf")

    @Test func unsyncedPDFCarriesTheFile() {
        #expect(CloudKitAssetUploadPolicy.pdfAssetURL(pdfURL, isSynced: false) == pdfURL)
    }

    /// A rename is the only post-sync PDF save; it must not re-send the document.
    @Test func syncedPDFSavesMetadataOnly() {
        #expect(CloudKitAssetUploadPolicy.pdfAssetURL(pdfURL, isSynced: true) == nil)
    }
}
