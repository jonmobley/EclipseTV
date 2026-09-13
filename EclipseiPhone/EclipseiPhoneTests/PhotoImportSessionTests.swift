//
//  PhotoImportSessionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct PhotoImportSessionTests {

    @Test func aBatchReadsAsOneBarAcrossItsPicks() {
        let session = PhotoImportSession()
        session.begin(total: 2)
        session.track(Progress(totalUnitCount: 10), at: 0)
        session.track(Progress(totalUnitCount: 10), at: 1)

        session.report(fraction: 0.5, at: 0)
        #expect(abs(session.fraction - 0.25) < 0.001)

        session.report(fraction: 1, at: 1)
        #expect(abs(session.fraction - 0.75) < 0.001)
    }

    /// KVO notifications are re-dispatched onto the main actor and can land out
    /// of order; a bar that slides backwards reads as a stall.
    @Test func progressNeverSlidesBackwards() {
        let session = PhotoImportSession()
        session.begin(total: 1)
        session.track(Progress(totalUnitCount: 10), at: 0)

        session.report(fraction: 0.8, at: 0)
        session.report(fraction: 0.3, at: 0)
        #expect(abs(session.fraction - 0.8) < 0.001)
    }

    @Test func finishingAPickCountsItWhole() {
        let session = PhotoImportSession()
        session.begin(total: 2)
        session.track(Progress(totalUnitCount: 10), at: 0)
        session.report(fraction: 0.4, at: 0)

        session.finish(at: 0)

        #expect(session.completed == 1)
        #expect(abs(session.fraction - 0.5) < 0.001)
    }

    @Test func cancellingStopsTheDownloadsInFlight() {
        let session = PhotoImportSession()
        let progress = Progress(totalUnitCount: 10)
        session.begin(total: 1)
        session.track(progress, at: 0)

        session.cancel()

        #expect(session.isCancelled)
        #expect(progress.isCancelled)
    }

    /// How the tail of a cancelled batch unwinds: a pick whose download starts
    /// after the Cancel tap is stopped as it arrives.
    @Test func aPickStartedAfterCancelIsStoppedImmediately() {
        let session = PhotoImportSession()
        session.begin(total: 2)
        session.cancel()

        let late = Progress(totalUnitCount: 10)
        session.track(late, at: 1)

        #expect(late.isCancelled)
    }

    @Test func startingABatchClearsTheLastOnesCancellation() {
        let session = PhotoImportSession()
        session.begin(total: 1)
        session.cancel()

        session.begin(total: 1)

        #expect(!session.isCancelled)
    }

    /// Most picks are already on the device and finish in milliseconds, so the
    /// overlay would be a flash of noise.
    @Test func nothingIsShownWhileTheImportMightStillBeInstant() {
        let session = PhotoImportSession()
        session.begin(total: 1)
        #expect(!session.isVisible)
    }

    @Test func theOverlayAppearsOnceTheWorkOutlastsTheDelay() async throws {
        let session = PhotoImportSession()
        session.begin(total: 1)
        try await Task.sleep(for: PhotoImportSession.revealDelay * 2)
        #expect(session.isVisible)
    }

    @Test func anImportThatFinishesFirstNeverShowsTheOverlay() async throws {
        let session = PhotoImportSession()
        session.begin(total: 1)
        session.end()
        try await Task.sleep(for: PhotoImportSession.revealDelay * 2)
        #expect(!session.isVisible)
    }

    @Test func endingTakesTheOverlayDown() async throws {
        let session = PhotoImportSession()
        session.begin(total: 1)
        try await Task.sleep(for: PhotoImportSession.revealDelay * 2)

        session.end()

        #expect(!session.isVisible)
    }
}
