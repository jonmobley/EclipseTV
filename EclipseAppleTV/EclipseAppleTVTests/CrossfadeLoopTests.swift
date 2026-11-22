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

    @Test func onlyShippedVideosBlend() {
        let bundled = ShippedVideo.bundledURLs.first
        #expect(bundled != nil)
        #expect(bundled.map { ImageViewController.crossfadesLoop(path: $0.path) } == true)
        #expect(ImageViewController.crossfadesLoop(path: "/old/Videos/Loop/video1.mp4"))
        #expect(!ImageViewController.crossfadesLoop(
            path: "/data/Containers/Data/Application/X/Library/Caches/Media/clip.mp4"))
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
