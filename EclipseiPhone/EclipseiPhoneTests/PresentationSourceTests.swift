//
//  PresentationSourceTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct PresentationSourceTests {

    @Test func videoAutoplaysByDefault() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        let source = PresentationSource.video(
            url, isLooping: false, isMuted: false, startAt: 3
        )
        #expect(source.videoAutoplay)
        #expect(source.videoStartAt == 3)
    }

    @Test func pausingVideoDisablesAutoplayAndUpdatesStart() {
        let url = URL(fileURLWithPath: "/tmp/clip.mp4")
        let source = PresentationSource.video(
            url, isLooping: true, isMuted: true, startAt: 3
        )
        let parked = source.pausingVideo(at: 9)
        #expect(parked.videoAutoplay == false)
        #expect(parked.videoStartAt == 9)
        #expect(parked.content == source.content)
    }

    @Test func pausingVideoIsNoOpForStills() {
        let url = URL(fileURLWithPath: "/tmp/still.jpg")
        let source = PresentationSource.image(url)
        let parked = source.pausingVideo(at: 4)
        #expect(parked == source)
    }
}
