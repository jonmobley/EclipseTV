//
//  LiveHeaderViewTransportAutoHideTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Phone-played hero video hides its transport like a video player; a TV-driven
/// hero never does.
@MainActor
struct LiveHeaderViewTransportAutoHideTests {

    @Test func tapOnPhoneVideoTucksAndRestoresTheTransport() {
        let header = makeHeaderPlayingOnPhone()
        guard header.transportAutoHides else { return } // VoiceOver keeps it up
        #expect(header.controls.alpha == 1)

        header.toggleTransportChrome()
        #expect(header.isTransportChromeTucked)
        #expect(header.controls.alpha == 0)
        #expect(header.heroExpandButton?.alpha == 0)

        header.toggleTransportChrome()
        #expect(!header.isTransportChromeTucked)
        #expect(header.controls.alpha == 1)
        #expect(header.heroExpandButton?.alpha == 1)
        header.clearLibraryVideoPreview()
    }

    @Test func pausedVideoBringsTheTransportBack() {
        let header = makeHeaderPlayingOnPhone()
        guard header.transportAutoHides else { return }
        header.toggleTransportChrome()
        #expect(header.isTransportChromeTucked)

        header.noteLibraryVideoPlaybackForTransport(isPlaying: false)
        #expect(!header.isTransportChromeTucked)
        #expect(header.transportAutoHideTimer == nil)
        header.clearLibraryVideoPreview()
    }

    @Test func leavingPhoneVideoResetsTheTransport() {
        let header = makeHeaderPlayingOnPhone()
        guard header.transportAutoHides else { return }
        header.toggleTransportChrome()
        header.clearLibraryVideoPreview()
        #expect(!header.isTransportChromeTucked)
        #expect(header.transportAutoHideTimer == nil)
    }

    /// AirPlay / Eclipse TV: the hero is a remote, so its transport stays put.
    @Test func tvDrivenHeroNeverTucks() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.wantsPlaybackControls = true
        header.applyCollapseChrome()
        #expect(!header.transportAutoHides)

        header.toggleTransportChrome()
        header.noteLibraryVideoPlaybackForTransport(isPlaying: true)
        #expect(!header.isTransportChromeTucked)
        #expect(header.transportAutoHideTimer == nil)
        #expect(header.controls.alpha == 1)
    }

    private func makeHeaderPlayingOnPhone() -> LiveHeaderView {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.wantsPlaybackControls = true
        header.showLibraryVideoPreview(
            url: URL(fileURLWithPath: "/nonexistent/hero-test.mov"),
            itemId: "hero-test",
            isMuted: true,
            isLooping: false,
            autoplay: false
        )
        header.applyCollapseChrome()
        return header
    }
}
