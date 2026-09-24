//
//  VideoPlaybackGenerationTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
@testable import EclipseAppleTV

struct VideoPlaybackGenerationTests {

    @Test func matchingGenerationAndPlayerMayPlay() {
        let player = AVPlayer()
        #expect(
            ImageViewController.shouldBeginPlayback(
                generation: 3,
                currentGeneration: 3,
                attachedPlayer: player,
                expectedPlayer: player
            )
        )
    }

    @Test func staleGenerationMustNotPlay() {
        let player = AVPlayer()
        #expect(
            !ImageViewController.shouldBeginPlayback(
                generation: 2,
                currentGeneration: 3,
                attachedPlayer: player,
                expectedPlayer: player
            )
        )
    }

    @Test func detachedPlayerMustNotPlay() {
        let expected = AVPlayer()
        let attached = AVPlayer()
        #expect(
            !ImageViewController.shouldBeginPlayback(
                generation: 1,
                currentGeneration: 1,
                attachedPlayer: attached,
                expectedPlayer: expected
            )
        )
        #expect(
            !ImageViewController.shouldBeginPlayback(
                generation: 1,
                currentGeneration: 1,
                attachedPlayer: nil,
                expectedPlayer: expected
            )
        )
    }
}
