//
//  PreviewDismissDriverTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct PreviewDismissDriverTests {

    // MARK: - Wiring

    @Test func imageGalleryCanBeDraggedClosed() {
        let gallery = makeImageGallery()

        #expect(gallery.transitioningDelegate != nil)
        #expect(dismissPans(on: gallery).count == 1)
    }

    @Test func showGalleryCanBeDraggedClosed() {
        let gallery = ShowPreviewViewController(
            items: [.still(LocalMediaPreviewItem(id: "a", fileURL: sampleURL(), isVideo: false))],
            startIndex: 0
        )
        gallery.loadViewIfNeeded()

        #expect(gallery.transitioningDelegate != nil)
        #expect(dismissPans(on: gallery).count == 1)
    }

    /// The gesture is invisible, so Close has to stay: VoiceOver and Switch Control
    /// need a focusable way off the screen.
    @Test func closeButtonSurvivesAlongsideTheGesture() {
        let gallery = makeImageGallery()

        let buttons = gallery.view.subviews
            .compactMap { $0 as? PreviewHeaderView }
            .map(\.closeButton)
        #expect(buttons.count == 1)
        #expect(buttons.first?.isHidden == false)
        #expect(buttons.first?.accessibilityLabel == "Close")
    }

    // MARK: - Transition ownership

    /// Tapping Close keeps UIKit's cover-vertical exit. The card animator is handed
    /// over only while a drag is driving it, so it must be absent at rest.
    @Test func tappingCloseUsesTheStockDismissalNotTheCard() {
        let gallery = makeImageGallery()
        guard let delegate = gallery.transitioningDelegate else {
            Issue.record("expected Preview to own a transitioning delegate")
            return
        }

        // Flattened: the optional-protocol call nests one optional of its own, and
        // `.some(nil)` is not `nil`.
        let dismissal = delegate.animationController?(forDismissed: gallery) ?? nil
        let presentation = delegate.animationController?(
            forPresented: gallery, presenting: gallery, source: gallery
        ) ?? nil
        #expect(dismissal == nil)
        #expect(presentation == nil)
    }

    /// Preview stays fullscreen: a detent sheet would inset it from the top and read
    /// as a secondary panel, which is what the note composer and settings already use.
    @Test func previewStaysFullscreenRatherThanBecomingASheet() {
        #expect(makeImageGallery().modalPresentationStyle == .fullScreen)
    }

    // MARK: - Helpers

    private func makeImageGallery() -> LocalMediaPreviewViewController {
        let gallery = LocalMediaPreviewViewController(
            items: [LocalMediaPreviewItem(id: "a", fileURL: sampleURL(), isVideo: false)],
            startIndex: 0
        )
        gallery.loadViewIfNeeded()
        return gallery
    }

    private func dismissPans(on controller: UIViewController) -> [UIPanGestureRecognizer] {
        (controller.view.gestureRecognizers ?? []).compactMap { $0 as? UIPanGestureRecognizer }
    }

    private func sampleURL() -> URL {
        URL(fileURLWithPath: "/tmp/eclipse-preview-dismiss.jpg")
    }
}
