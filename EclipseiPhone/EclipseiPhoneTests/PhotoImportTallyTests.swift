//
//  PhotoImportTallyTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct PhotoImportTallyTests {

    @Test func aCleanImportJustReportsTheCount() {
        var tally = PhotoImportTally()
        tally.added = 4
        #expect(tally.statusMessage == "Added 4")
    }

    /// An asset stuck in iCloud and an asset we declined are different problems,
    /// and reading "skipped" for the first one tells the user nothing to act on.
    @Test func downloadFailuresAreCountedApartFromSkips() {
        var tally = PhotoImportTally()
        tally.added = 3
        tally.record(.iCloudDownload)
        tally.record(.iCloudDownload)
        tally.record(.unreadable)
        #expect(tally.iCloudFailures == 2)
        #expect(tally.skipped == 1)
        #expect(tally.statusMessage == "Added 3, 2 not downloaded, 1 skipped")
    }

    @Test func downloadFailuresAloneReadAsADownloadProblem() {
        var tally = PhotoImportTally()
        tally.added = 1
        tally.record(.iCloudDownload)
        #expect(tally.statusMessage == "Added 1, 1 not downloaded")
    }

    @Test func skipsAloneKeepTheOriginalWording() {
        var tally = PhotoImportTally()
        tally.added = 2
        tally.record(.unreadable)
        #expect(tally.statusMessage == "Added 2, 1 skipped")
    }

    @Test func nothingAddedAndNothingDownloadedBlamesTheDownload() {
        var tally = PhotoImportTally()
        tally.record(.iCloudDownload)
        #expect(tally.statusMessage == "Couldn't download from iCloud")
    }

    @Test func nothingAddedForOtherReasonsKeepsTheOriginalWording() {
        var tally = PhotoImportTally()
        tally.record(.unreadable)
        #expect(tally.statusMessage == "Couldn't import selection")
    }

    /// Stopping partway still keeps what already came down.
    @Test func cancellingReportsWhatSurvived() {
        var tally = PhotoImportTally()
        tally.added = 2
        tally.record(.cancelled)
        #expect(tally.wasCancelled)
        #expect(tally.statusMessage == "Stopped — added 2")
    }

    @Test func cancellingWithNothingAddedSaysSo() {
        var tally = PhotoImportTally()
        tally.record(.cancelled)
        #expect(tally.statusMessage == "Import stopped")
    }

    @Test func slideshowSuccessCarriesTheShortfall() {
        var tally = PhotoImportTally()
        tally.added = 5
        tally.record(.iCloudDownload)
        #expect(tally.slideshowMessage == "Slideshow created, 1 not downloaded")
    }

    @Test func slideshowSuccessWithoutShortfallStaysShort() {
        var tally = PhotoImportTally()
        tally.added = 5
        #expect(tally.slideshowMessage == "Slideshow created")
    }

    @Test func slideshowFailureBlamesTheDownloadWhenThatIsWhatHappened() {
        var tally = PhotoImportTally()
        tally.record(.iCloudDownload)
        #expect(tally.slideshowFailureMessage == "Couldn't download from iCloud")
        #expect(PhotoImportTally().slideshowFailureMessage == "Couldn't create Slideshow")
    }

    @Test func mergingAddsTheCountsAndKeepsACancellation() {
        var first = PhotoImportTally()
        first.added = 1
        first.record(.unreadable)
        var second = PhotoImportTally()
        second.added = 2
        second.record(.iCloudDownload)
        second.record(.cancelled)
        first.merge(second)
        #expect(first == PhotoImportTally(
            added: 3, iCloudFailures: 1, skipped: 1, wasCancelled: true
        ))
    }

    @Test func retryCopyMatchesTheNumberLeftBehind() {
        var one = PhotoImportTally()
        one.record(.iCloudDownload)
        #expect(one.iCloudRetryMessage.contains("One item hasn't"))
        var several = PhotoImportTally()
        several.record(.iCloudDownload)
        several.record(.iCloudDownload)
        #expect(several.iCloudRetryMessage.contains("2 items haven't"))
    }

    // MARK: - In-flight copy

    @Test func aSinglePickExplainsTheWait() {
        #expect(
            PhotoImportProgressCopy.title(completed: 0, total: 1)
                == "Downloading from iCloud…"
        )
    }

    @Test func aBatchCountsThroughItsPicks() {
        #expect(PhotoImportProgressCopy.title(completed: 0, total: 8) == "Importing 1 of 8…")
        #expect(PhotoImportProgressCopy.title(completed: 3, total: 8) == "Importing 4 of 8…")
    }

    /// The last finish arrives before the overlay comes down.
    @Test func theCounterNeverOvershootsTheTotal() {
        #expect(PhotoImportProgressCopy.title(completed: 8, total: 8) == "Importing 8 of 8…")
    }
}
