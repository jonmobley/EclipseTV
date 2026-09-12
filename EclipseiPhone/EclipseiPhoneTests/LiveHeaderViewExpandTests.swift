//
//  LiveHeaderViewExpandTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewExpandTests {

    @Test func websiteHeroShowsTheExpandControl() {
        let header = makeHeader()
        header.allowsOverlayControllerTap = true
        header.syncExpandControl()
        #expect(header.heroExpandTarget == .overlayController)
        #expect(header.heroExpandButton != nil)
        #expect(header.heroExpandButton?.accessibilityLabel == "Full Screen")
    }

    @Test func cameraHeroShowsTheExpandControl() {
        let header = makeHeader()
        header.allowsCameraControllerTap = true
        header.syncExpandControl()
        #expect(header.heroExpandTarget == .cameraController)
        #expect(header.heroExpandButton?.accessibilityLabel == "Camera Controls")
    }

    @Test func libraryVideoHeroShowsTheExpandControl() {
        let header = makeHeader()
        header.setLibraryVideoFullscreenAvailable(true)
        #expect(header.heroExpandTarget == .fullscreenPreview)
        #expect(header.heroExpandButton?.accessibilityLabel == "Full Screen")

        header.setLibraryVideoFullscreenAvailable(false)
        #expect(header.heroExpandButton == nil)
    }

    /// CONTROLS is a half sheet, so an expand glyph would promise the wrong thing.
    @Test func livePollHeroKeepsTheBodyTapWithoutAControl() {
        let header = makeHeader()
        header.allowsHostControllerTap = true
        header.syncExpandControl()
        #expect(header.heroExpandTarget == .hostController)
        #expect(header.heroExpandButton == nil)
        #expect(header.isUserInteractionEnabled == true)
    }

    @Test func heroWithNothingLiveHasNoExpandControl() {
        let header = makeHeader()
        header.syncExpandControl()
        #expect(header.heroExpandTarget == nil)
        #expect(header.heroExpandButton == nil)
        #expect(header.isUserInteractionEnabled == false)
    }

    @Test func clearingAffordancesRemovesTheControl() {
        let header = makeHeader()
        header.allowsOverlayControllerTap = true
        header.syncExpandControl()
        #expect(header.heroExpandButton != nil)

        header.resetTapAffordances()
        header.syncExpandControl()
        #expect(header.heroExpandButton == nil)
    }

    /// The control and the body tap must open the same surface.
    @Test func controlAndBodyTapRequestTheSameSurface() {
        let header = makeHeader()
        var overlayRequests = 0
        var cameraRequests = 0
        header.onRequestOverlayController = { overlayRequests += 1 }
        header.onRequestCameraController = { cameraRequests += 1 }

        header.allowsOverlayControllerTap = true
        header.syncExpandControl()
        header.heroExpandButton?.sendActions(for: .touchUpInside)
        header.handleFullscreenContentTap()
        #expect(overlayRequests == 2)
        #expect(cameraRequests == 0)
    }

    /// Camera outranks a website so a stale flag cannot claim the newer hero.
    @Test func cameraOutranksWebsiteWhenBothFlagsAreSet() {
        let header = makeHeader()
        header.allowsCameraControllerTap = true
        header.allowsOverlayControllerTap = true
        #expect(header.heroExpandTarget == .cameraController)
    }

    @Test func expandRequestIsRefusedWhenNothingIsLive() {
        let header = makeHeader()
        var fullscreenRequests = 0
        header.onRequestFullscreen = { fullscreenRequests += 1 }
        #expect(header.requestExpandedPresentation() == false)
        #expect(fullscreenRequests == 0)
    }

    /// The tucked mini preview taps to expand, so the control must not sit on it.
    @Test func collapsedHeroHidesTheExpandControl() {
        let header = makeHeader()
        header.allowsOverlayControllerTap = true
        header.syncExpandControl()
        header.applyCollapse(progress: 1, scale: 0.35)
        #expect(header.heroExpandButton?.isHidden == true)

        header.applyCollapse(progress: 0, scale: 1)
        #expect(header.heroExpandButton?.isHidden == false)
    }

    private func makeHeader() -> LiveHeaderView {
        LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}
