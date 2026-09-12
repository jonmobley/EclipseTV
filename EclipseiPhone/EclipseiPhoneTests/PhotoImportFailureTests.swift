//
//  PhotoImportFailureTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct PhotoImportFailureTests {

    @Test func aMissingErrorIsJustUnreadable() {
        #expect(PhotoImportFailure.classify(nil) == .unreadable)
    }

    @Test func photosICloudTransferErrorsReadAsADownload() {
        let error = NSError(domain: "CloudPhotoLibraryErrorDomain", code: 82)
        #expect(PhotoImportFailure.classify(error) == .iCloudDownload)
    }

    @Test func networkAccessRequiredReadsAsADownload() {
        let error = NSError(domain: "PHPhotosErrorDomain", code: 3164)
        #expect(PhotoImportFailure.classify(error) == .iCloudDownload)
    }

    /// Other Photos errors are not the user's connection to fix.
    @Test func otherPhotosErrorsAreUnreadable() {
        let error = NSError(domain: "PHPhotosErrorDomain", code: 3300)
        #expect(PhotoImportFailure.classify(error) == .unreadable)
    }

    @Test func urlErrorsReadAsADownload() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        #expect(PhotoImportFailure.classify(error) == .iCloudDownload)
    }

    /// Photos buries the interesting domain under a generic wrapper.
    @Test func anUnderlyingNetworkErrorIsFound() {
        let underlying = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSFileReadUnknownError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        #expect(PhotoImportFailure.classify(error) == .iCloudDownload)
    }

    @Test func stoppingADownloadReadsAsCancelled() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)
        #expect(PhotoImportFailure.classify(error) == .cancelled)
    }

    @Test func swiftCancellationReadsAsCancelled() {
        #expect(PhotoImportFailure.classify(CancellationError()) == .cancelled)
    }

    /// Cancelling an in-flight iCloud fetch reports both; the user's own action
    /// is the honest explanation.
    @Test func cancellationOutranksTheNetworkFailureItCauses() {
        let underlying = NSError(domain: "CloudPhotoLibraryErrorDomain", code: 82)
        let error = NSError(
            domain: NSCocoaErrorDomain,
            code: NSUserCancelledError,
            userInfo: [NSUnderlyingErrorKey: underlying]
        )
        #expect(PhotoImportFailure.classify(error) == .cancelled)
    }

    @Test func anErrorThatPointsAtItselfDoesNotLoop() {
        let error = NSError(domain: "Weird", code: 1)
        let looping = NSError(
            domain: "Weird",
            code: 2,
            userInfo: [NSUnderlyingErrorKey: error]
        )
        #expect(PhotoImportFailure.classify(looping) == .unreadable)
    }

    @Test func onlyADownloadIsWorthRetrying() {
        #expect(PhotoImportFailure.iCloudDownload.isWorthRetrying)
        #expect(!PhotoImportFailure.unreadable.isWorthRetrying)
        #expect(!PhotoImportFailure.cancelled.isWorthRetrying)
    }

    @Test func theDownloadMessageNamesWhatWasPicked() {
        let message = PhotoImportFailure.iCloudDownload.message(noun: "video")
        #expect(message.contains("video"))
        #expect(message.contains("iCloud"))
    }
}
