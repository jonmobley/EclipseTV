//
//  AudioAmbientPolicyTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import Testing
@testable import EclipseiPhone

@Suite(.serialized)
struct AudioAmbientPolicyTests {

    @Test func defaultDoesNotYieldToAudibleVideo() {
        withPauseMusicForVideo(false) {
            #expect(AudioAmbientPolicy.shouldYield(to: video(isMuted: false)) == false)
            #expect(AudioAmbientPolicy.presentationAudioMode == .default)
        }
    }

    @Test func preferenceYieldsToAudibleVideoOnly() {
        withPauseMusicForVideo(true) {
            #expect(AudioAmbientPolicy.shouldYield(to: video(isMuted: false)))
            #expect(AudioAmbientPolicy.shouldYield(to: video(isMuted: true)) == false)
            #expect(AudioAmbientPolicy.presentationAudioMode == .moviePlayback)
        }
    }

    @Test func defaultDoesNotYieldToWebMedia() throws {
        let event = try #require(webEvent(action: "play", paused: false, muted: false))
        withPauseMusicForVideo(false) {
            #expect(AudioAmbientPolicy.shouldYield(toWebMedia: event) == false)
        }
    }

    @Test func preferenceYieldsToUnmutedWebPlay() throws {
        let play = try #require(webEvent(action: "play", paused: false, muted: false))
        let muted = try #require(webEvent(action: "play", paused: false, muted: true))
        let paused = try #require(webEvent(action: "play", paused: true, muted: false))
        withPauseMusicForVideo(true) {
            #expect(AudioAmbientPolicy.shouldYield(toWebMedia: play))
            #expect(AudioAmbientPolicy.shouldYield(toWebMedia: muted) == false)
            #expect(AudioAmbientPolicy.shouldYield(toWebMedia: paused) == false)
        }
    }
}

private func withPauseMusicForVideo(_ value: Bool, _ body: () -> Void) {
    let previous = ExternalOutputSettings.pauseMusicForVideo
    ExternalOutputSettings.pauseMusicForVideo = value
    defer { ExternalOutputSettings.pauseMusicForVideo = previous }
    body()
}

private func video(isMuted: Bool) -> PresentationSource {
    PresentationSource.video(
        URL(fileURLWithPath: "/tmp/clip.mp4"),
        isLooping: false,
        isMuted: isMuted
    )
}

private func webEvent(
    action: String,
    paused: Bool,
    muted: Bool
) -> EclipseWebMediaSync.Event? {
    EclipseWebMediaSync.Event(messageBody: [
        "action": action,
        "paused": paused,
        "muted": muted
    ] as [String: Any])
}
