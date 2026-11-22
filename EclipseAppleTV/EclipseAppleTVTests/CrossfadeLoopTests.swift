//
//  CrossfadeLoopTests.swift
//  EclipseAppleTVTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
@testable import EclipseAppleTV

@MainActor
struct CrossfadeLoopTests {

    @Test func shippedVideosBlendUnlessTurnedOff() {
        let bundled = ShippedVideo.bundledURLs.first
        #expect(bundled != nil)
        let defaults = AppState.VideoSettings()
        #expect(bundled.map { ImageViewController.crossfadesLoop(path: $0.path, settings: defaults) } == true)
        var off = defaults
        off.crossfadesLoop = false
        #expect(bundled.map { ImageViewController.crossfadesLoop(path: $0.path, settings: off) } == false)
    }

    @Test func phoneVideosBlendOnlyWhenTurnedOn() {
        let phoneVideo = "/data/Containers/Data/Application/X/Library/Caches/Media/clip.mp4"
        var settings = AppState.VideoSettings()
        #expect(!ImageViewController.crossfadesLoop(path: phoneVideo, settings: settings))
        settings.crossfadesLoop = true
        #expect(ImageViewController.crossfadesLoop(path: phoneVideo, settings: settings))
    }

    @Test func olderSavedSettingsStillDecode() throws {
        let old = Data(#"{"isLooping":true,"isMuted":false,"volume":1,"playbackRate":1,"lastPosition":0}"#.utf8)
        let decoded = try JSONDecoder().decode(AppState.VideoSettings.self, from: old)
        #expect(decoded.isLooping)
        #expect(decoded.crossfadesLoop == nil)
    }

    @Test func settingMessageCarriesTheChoice() throws {
        let envelope = EclipseShareEnvelope.setVideoSetting(
            id: "clip.mp4", isLooping: true, isMuted: nil, crossfadesLoop: true
        )
        let decoded = try JSONDecoder().decode(
            EclipseShareEnvelope.self, from: JSONEncoder().encode(envelope)
        )
        #expect(decoded.crossfadesLoop == true)
    }

    @Test func shippedVideosLoopByDefault() {
        let state = AppState()
        let bundled = ShippedVideo.bundledURLs.first?.path ?? "/x/Eclipse.app/video1.mp4"
        #expect(state.getVideoSettings(for: bundled).isLooping)
        #expect(!state.getVideoSettings(for: "/x/Library/Caches/Media/new-\(UUID()).mp4").isLooping)
    }

    @Test func timingDissolvesTheEndIntoTheStart() {
        let timing = CrossfadeLoopTiming(
            duration: CMTime(seconds: 10, preferredTimescale: 600),
            fade: CMTime(seconds: 1, preferredTimescale: 600)
        )
        #expect(abs(timing.outputDuration.seconds - 9) < 0.001)
        #expect(abs(timing.fadeRange.start.seconds - 8) < 0.001)
        #expect(abs(timing.tailSource.start.seconds - 1) < 0.001)
        #expect(abs(timing.headSource.end.seconds - 1) < 0.001)
    }

    @Test func damagedFrameRatesFallBackSafely() {
        #expect(CrossfadeLoopComposer.frameTimescale(for: 24) == 24)
        #expect(CrossfadeLoopComposer.frameTimescale(for: .nan) == 30)
        #expect(CrossfadeLoopComposer.frameTimescale(for: 0) == 30)
        #expect(CrossfadeLoopComposer.frameTimescale(for: 1e12) == 240)
    }

    @Test func bundledLoopBuildsABlendedItem() async throws {
        let url = try #require(ShippedVideo.bundledURLs.first)
        await CrossfadeLoopComposer.prepare(url)
        let item = try #require(CrossfadeLoopComposer.cachedItem(for: url))
        let source = try await AVURLAsset(url: url).load(.duration)
        let output = try await item.asset.load(.duration)
        #expect(item.videoComposition != nil)
        #expect(abs(output.seconds - (source.seconds - CrossfadeLoopComposer.fadeSeconds)) < 0.05)
    }
}
