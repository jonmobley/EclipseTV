//
//  ScreensaverTransitionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ScreensaverTransitionTests {

    @Test func sameScreensaverDoesNotRebuildPlayer() {
        let vc = PresentationViewController()
        _ = vc.view
        let url = URL(fileURLWithPath: "/tmp/eclipse-ss-keep.mp4")
        let source = PresentationSource.screensaver(url)
        vc.applyShowDirect(source)
        let first = vc.screensaverView
        #expect(first != nil)
        #expect(vc.shouldSkipScreensaverReshow(source))
        vc.show(source)
        #expect(vc.screensaverView === first)
    }

    @Test func inFlightShowIsNotRestarted() {
        let vc = PresentationViewController()
        _ = vc.view
        let source = PresentationSource.screensaver(
            URL(fileURLWithPath: "/tmp/eclipse-ss-inflight.mp4")
        )
        vc.show(source)
        #expect(vc.isTransitionInFlight)
        let generation = vc.transitionGeneration
        vc.show(source)
        #expect(vc.transitionGeneration == generation)
    }

    @Test func differentScreensaverDoesNotSkip() {
        let vc = PresentationViewController()
        _ = vc.view
        vc.applyShowDirect(
            PresentationSource.screensaver(URL(fileURLWithPath: "/tmp/ss-a.mp4"))
        )
        let next = PresentationSource.screensaver(
            URL(fileURLWithPath: "/tmp/ss-b.mp4")
        )
        #expect(vc.shouldSkipScreensaverReshow(next) == false)
    }

    @Test func togglingCrossfadeDoesNotSkipReshow() {
        let vc = PresentationViewController()
        _ = vc.view
        let url = URL(fileURLWithPath: "/tmp/eclipse-ss-fade.mp4")
        vc.applyShowDirect(PresentationSource.screensaver(url, crossfade: true))
        #expect(vc.shouldSkipScreensaverReshow(.screensaver(url, crossfade: true)))
        #expect(vc.shouldSkipScreensaverReshow(.screensaver(url, crossfade: false)) == false)
    }

    @Test func screensaverSourceDefaultsToCrossfade() {
        let url = URL(fileURLWithPath: "/tmp/eclipse-ss-default.mp4")
        #expect(PresentationSource.screensaver(url) == .screensaver(url, crossfade: true))
    }

    @Test func loopPlayerHonoursCrossfadeMode() {
        let url = URL(fileURLWithPath: "/tmp/eclipse-ss-mode.mp4")
        #expect(SeamlessLoopPlayerView(url: url).crossfadesAtLoop)
        #expect(SeamlessLoopPlayerView(url: url, crossfadesAtLoop: false).crossfadesAtLoop == false)
    }

    @Test func screensaverPreviewKeepsPosterUntilFrame() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.configureOverlay(
            title: "Screensaver",
            systemImage: "sparkles.tv",
            fillColor: UIColor(white: 0.12, alpha: 1),
            thumbnail: UIImage(),
            keepScreensaverPreview: false
        )
        header.showScreensaverPreview()
        #expect(header.imageView.alpha == 1)
    }
}
