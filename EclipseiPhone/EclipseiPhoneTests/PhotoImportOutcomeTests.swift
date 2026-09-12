//
//  PhotoImportOutcomeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct PhotoImportOutcomeTests {

    private func prepared(index: Int) -> PhotoImportPrepared {
        PhotoImportPrepared(
            index: index,
            localURL: URL(fileURLWithPath: "/tmp/pick-\(index).jpg"),
            isVideo: false,
            thumbnail: nil,
            duration: 0
        )
    }

    /// Downloads finish out of order — a small still beats a 4K movie — so the
    /// library add order comes from the selection, not from who arrived first.
    @Test func preparedFilesAreReplayedInPickOrder() {
        var outcome = PhotoImportOutcome()
        outcome.record(.success(prepared(index: 2)), at: 2)
        outcome.record(.success(prepared(index: 0)), at: 0)
        outcome.record(.success(prepared(index: 1)), at: 1)
        #expect(outcome.preparedInPickOrder.map(\.index) == [0, 1, 2])
    }

    @Test func onlyDownloadFailuresAreOfferedAnotherAttempt() {
        var outcome = PhotoImportOutcome()
        outcome.record(.failure(.iCloudDownload), at: 0)
        outcome.record(.failure(.unreadable), at: 1)
        outcome.record(.failure(.cancelled), at: 2)
        outcome.record(.failure(.iCloudDownload), at: 3)
        #expect(outcome.retryableIndexes == [0, 3])
        #expect(outcome.tally.iCloudFailures == 2)
        #expect(outcome.tally.skipped == 1)
        #expect(outcome.tally.wasCancelled)
    }

    @Test func mergingKeepsBothPhasesFilesAndRetries() {
        var stills = PhotoImportOutcome()
        stills.record(.success(prepared(index: 0)), at: 0)
        stills.record(.failure(.iCloudDownload), at: 1)
        var movies = PhotoImportOutcome()
        movies.record(.success(prepared(index: 2)), at: 2)
        movies.record(.failure(.iCloudDownload), at: 3)

        stills.merge(movies)

        #expect(stills.preparedInPickOrder.map(\.index) == [0, 2])
        #expect(stills.retryableIndexes == [1, 3])
        #expect(stills.tally.iCloudFailures == 2)
    }

    @Test @MainActor func theCollectorGathersWhatTheConcurrentPhaseProduces() {
        let collector = PhotoImportCollector()
        collector.record(.success(prepared(index: 1)), at: 1)
        collector.record(.failure(.iCloudDownload), at: 0)
        #expect(collector.outcome.prepared.count == 1)
        #expect(collector.outcome.retryableIndexes == [0])
    }
}
