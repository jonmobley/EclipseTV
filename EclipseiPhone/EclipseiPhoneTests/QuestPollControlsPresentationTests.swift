//
//  QuestPollControlsPresentationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct QuestPollControlsPresentationTests {

    // MARK: - Sheet chrome

    @Test func controlsRestHalfHeightSoTheLivePreviewStaysVisible() {
        let sheet = makeControls().sheetPresentationController

        #expect(sheet?.detents.count == 2)
        #expect(sheet?.selectedDetentIdentifier == .medium)
        #expect(sheet?.prefersGrabberVisible == true)
        // Landscape parks the hero in the leading column; a full-height sheet
        // there would cover it.
        #expect(sheet?.prefersEdgeAttachedInCompactHeight == true)
    }

    /// Undimmed is the load-bearing part. Dimmed, the ribbon behind would be
    /// visible but inert, so the host could not cue without closing Controls.
    @Test func theShowBehindStaysUndimmedAndTappable() {
        let sheet = makeControls().sheetPresentationController

        #expect(sheet?.largestUndimmedDetentIdentifier == .medium)
    }

    /// Controls scroll inside the sheet. Allowed to expand, hitting the scroll
    /// edge would snap it to full height over the preview it is meant to reveal.
    @Test func scrollingControlsDoesNotExpandOverThePreview() {
        let sheet = makeControls().sheetPresentationController

        #expect(sheet?.prefersScrollingExpandsWhenScrolledToEdge == false)
    }

    // MARK: - Wiring

    /// Tapping the hero while Controls are already up must not stack a second
    /// sheet, and the de-dup check looks for this exact root controller.
    @Test func controlsAreTheNavigationRootSoRepeatTapsDeDup() {
        #expect(makeControls().viewControllers.first is QuestPollHostViewController)
    }

    @Test func advanceActionsReachTheRoom() {
        var sent: [String] = []
        let nav = QuestPollHostViewController.makeNavigation(
            onAdvance: { sent.append($0) },
            onEnd: nil
        )

        (nav.viewControllers.first as? QuestPollHostViewController)?.onAdvance?("next")
        #expect(sent == ["next"])
    }

    // MARK: - Helpers

    private func makeControls() -> UINavigationController {
        QuestPollHostViewController.makeNavigation(onAdvance: nil, onEnd: nil)
    }
}
