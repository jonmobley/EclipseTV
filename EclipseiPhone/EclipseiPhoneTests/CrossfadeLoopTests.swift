//
//  CrossfadeLoopTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct CrossfadeLoopTests {

    private func video(crossfade: Bool?) -> LibraryItemDTO {
        var item = LibraryItemDTO(id: "clip.mp4", name: "clip.mp4", isVideo: true, duration: 10)
        item.isLooping = true
        item.crossfadesLoop = crossfade
        return item
    }

    @Test func olderLibraryListsStillDecode() throws {
        let old = Data(#"{"id":"a.mp4","name":"a.mp4","isVideo":true,"duration":4,"isLooping":true}"#.utf8)
        let item = try JSONDecoder().decode(LibraryItemDTO.self, from: old)
        #expect(item.isLooping == true)
        #expect(item.crossfadesLoop == nil)
    }

    @Test func choiceTravelsInTheLibraryList() throws {
        let decoded = try JSONDecoder().decode(
            LibraryItemDTO.self, from: JSONEncoder().encode(video(crossfade: true))
        )
        #expect(decoded.crossfadesLoop == true)
    }

    @Test func settingMessageCarriesTheChoice() throws {
        let envelope = EclipseShareEnvelope.setVideoSetting(
            id: "clip.mp4", isLooping: nil, isMuted: nil, crossfadesLoop: false
        )
        let decoded = try JSONDecoder().decode(
            EclipseShareEnvelope.self, from: JSONEncoder().encode(envelope)
        )
        #expect(decoded.crossfadesLoop == false)
        #expect(decoded.isLooping == nil)
    }

    @Test func presentationKeepsTheChoiceWhenParked() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        let source = PresentationSource.video(url, isLooping: true, isMuted: true, crossfadesLoop: true)
        #expect(source.videoCrossfadesLoop)
        #expect(source.pausingVideo(at: 3).videoCrossfadesLoop)
        let plain = PresentationSource.video(url, isLooping: true, isMuted: true)
        #expect(!plain.videoCrossfadesLoop)
        #expect(source != plain)
    }

    @Test func bundledScreensaverBuildsABlend() async throws {
        let url = try #require(Bundle.main.url(forResource: "EclipseScreensaver", withExtension: "mp4"))
        await CrossfadeLoopComposer.prepare(url)
        #expect(CrossfadeLoopComposer.hasBlend(for: url))
        let item = try #require(CrossfadeLoopComposer.cachedItem(for: url))
        #expect(item.videoComposition != nil)
        let missing = URL(fileURLWithPath: "/tmp/missing-\(UUID()).mp4")
        await CrossfadeLoopComposer.prepare(missing)
        #expect(CrossfadeLoopComposer.isPrepared(missing))
        #expect(!CrossfadeLoopComposer.hasBlend(for: missing))
    }
}
