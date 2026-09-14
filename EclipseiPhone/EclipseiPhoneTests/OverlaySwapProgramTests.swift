//
//  OverlaySwapProgramTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

/// An overlay swap must never be observable as "nothing is live".
///
/// `ExternalDisplayManager` ends the outgoing overlay by posting a notification,
/// synchronously, and the Show grid repaints from `ShowProgramResolver` when it
/// arrives. While the outgoing overlay's id was cleared before `overlaySource`
/// moved on, that repaint saw an overlay no store claimed and dropped the red
/// stroke from every tile — or left it on the item that had just been replaced.
/// So each case here samples program *inside* the teardown notification.
@MainActor
struct OverlaySwapProgramTests {

    private let url = URL(string: "https://example.com")!

    @Test func aWebsiteHandingOffToACountdownIsCountdownBeforeItAnnouncesTheEnd() {
        let mgr = ExternalDisplayManager.shared
        clearOverlays()
        let pageId = UUID()
        mgr.presentWeb(url, pageId: pageId)
        #expect(Self.program() == ShowProgram(kind: .web, itemId: pageId.uuidString))

        let countdown = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
        let observed = Observed()
        let token = observe(ExternalDisplayManager.webDidEndNotification, into: observed)
        defer { NotificationCenter.default.removeObserver(token) }

        CountdownController.shared.prepare(countdown)
        mgr.presentCountdown()

        let expected = ShowProgram(kind: .countdown, itemId: countdown.id.uuidString)
        #expect(observed.programs == [expected])
        #expect(Self.program() == expected)
        #expect(mgr.liveWebPageId == nil)
        clearOverlays()
    }

    @Test func aCameraHandingOffToAWebsiteIsTheWebsiteBeforeItAnnouncesTheEnd() {
        let mgr = ExternalDisplayManager.shared
        clearOverlays()
        mgr.presentCamera()
        #expect(Self.program() == ShowProgram(kind: .camera))

        let pageId = UUID()
        let observed = Observed()
        let token = observe(ExternalDisplayManager.cameraDidEndNotification, into: observed)
        defer { NotificationCenter.default.removeObserver(token) }

        mgr.presentWeb(url, pageId: pageId)

        let expected = ShowProgram(kind: .web, itemId: pageId.uuidString)
        #expect(observed.programs == [expected])
        #expect(Self.program() == expected)
        clearOverlays()
    }

    @Test func aPDFHandingOffToAWebsiteDropsOnlyItsOwnId() {
        let mgr = ExternalDisplayManager.shared
        clearOverlays()
        let documentId = UUID()
        mgr.presentPDF(URL(fileURLWithPath: "/tmp/runsheet.pdf"), documentId: documentId)
        #expect(Self.program() == ShowProgram(kind: .pdf, itemId: documentId.uuidString))

        let pageId = UUID()
        let observed = Observed()
        let token = observe(ExternalDisplayManager.pdfDidEndNotification, into: observed)
        defer { NotificationCenter.default.removeObserver(token) }

        mgr.presentWeb(url, pageId: pageId)

        let expected = ShowProgram(kind: .web, itemId: pageId.uuidString)
        #expect(observed.programs == [expected])
        #expect(mgr.livePDFDocumentId == nil)
        #expect(mgr.liveWebPageId == pageId)
        clearOverlays()
    }

    /// Two countdowns are one overlay kind, so the swap is silent — but the clock
    /// still has to name the timer the user just tapped, and only that one.
    @Test func swappingCountdownsMovesTheLiveTimerWithoutEndingTheOverlay() {
        let mgr = ExternalDisplayManager.shared
        clearOverlays()
        let first = ShowCountdown(showId: UUID(), name: "Break", duration: 60)
        let second = ShowCountdown(showId: UUID(), name: "Doors", duration: 90)

        CountdownController.shared.prepare(first)
        mgr.presentCountdown()
        #expect(Self.program() == ShowProgram(kind: .countdown, itemId: first.id.uuidString))

        CountdownController.shared.prepare(second)
        mgr.presentCountdown()
        #expect(Self.program() == ShowProgram(kind: .countdown, itemId: second.id.uuidString))
        #expect(CountdownController.shared.liveCountdownId == second.id)
        clearOverlays()
    }

    // MARK: - Helpers

    /// The overlay half of what `LibraryGridViewController` samples for the grid.
    private static func program() -> ShowProgram? {
        let mgr = ExternalDisplayManager.shared
        var state = ShowProgramState()
        state.isOverlayLive = mgr.isOverlayLive
        state.isCameraTileLive = mgr.isCameraTileLive
        state.countdownId = mgr.isCountdownLive
            ? CountdownController.shared.liveCountdownId
            : nil
        state.webPageId = mgr.isWebLive ? mgr.liveWebPageId : nil
        state.webVideoPageId = mgr.isWebVideoLive ? mgr.liveWebVideoPageId : nil
        state.pdfDocumentId = mgr.isPDFLive ? mgr.livePDFDocumentId : nil
        return ShowProgramResolver.resolve(state)
    }

    private func observe(
        _ name: Notification.Name,
        into observed: Observed
    ) -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: name,
            object: nil,
            queue: nil
        ) { _ in
            MainActor.assumeIsolated {
                observed.programs.append(Self.program())
            }
        }
    }

    private func clearOverlays() {
        let mgr = ExternalDisplayManager.shared
        mgr.resumeCameraFromStillPark()
        if mgr.isCameraModeActive {
            mgr.stopCameraAndRestoreLibrary()
        }
        if mgr.isOverlayLive {
            mgr.stopWebAndRestoreLibrary()
        }
        CountdownController.shared.endLive()
    }

    /// Program sampled at each teardown notification, in arrival order.
    @MainActor
    private final class Observed {
        var programs: [ShowProgram?] = []
    }
}
