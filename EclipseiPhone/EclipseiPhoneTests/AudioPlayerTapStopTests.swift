//
//  AudioPlayerTapStopTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import Foundation
@testable import EclipseiPhone

@MainActor
struct AudioPlayerTapStopTests {

    @Test func tappingCurrentPlayingTrackStops() {
        let id = UUID()
        #expect(
            AudioPlayerController.tapStopsPlayback(
                isPlaying: true,
                currentTrackId: id,
                tappedTrackId: id
            )
        )
    }

    @Test func tappingADifferentTrackKeepsPlaying() {
        #expect(
            AudioPlayerController.tapStopsPlayback(
                isPlaying: true,
                currentTrackId: UUID(),
                tappedTrackId: UUID()
            ) == false
        )
    }

    @Test func tappingPausedCurrentTrackDoesNotStop() {
        let id = UUID()
        #expect(
            AudioPlayerController.tapStopsPlayback(
                isPlaying: false,
                currentTrackId: id,
                tappedTrackId: id
            ) == false
        )
    }
}
