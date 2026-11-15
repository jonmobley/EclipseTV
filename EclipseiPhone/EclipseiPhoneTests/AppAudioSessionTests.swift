//
//  AppAudioSessionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
@testable import EclipseiPhone

/// Other apps' music (Spotify…) keeps playing unless the user asked video to pause it.
struct AppAudioSessionTests {

    @Test func audibleVideoMixesWithOtherAppsByDefault() {
        #expect(AppAudioSession.presentationOptions(pauseMusicForVideo: false) == [.mixWithOthers])
    }

    @Test func pauseMusicForVideoTakesOverAudio() {
        #expect(AppAudioSession.presentationOptions(pauseMusicForVideo: true).isEmpty)
    }
}
