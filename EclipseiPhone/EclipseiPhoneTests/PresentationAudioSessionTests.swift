//
//  PresentationAudioSessionTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import AVFoundation
import Testing
@testable import EclipseiPhone

@Suite(.serialized)
struct PresentationAudioSessionTests {

    @Test func mutedDoesNotActivate() {
        PresentationAudioSession.reset()
        PresentationAudioSession.activateIfNeeded(muted: true)
        // Second call with muted must stay a no-op even after a real activate.
        PresentationAudioSession.activateIfNeeded(muted: false)
        PresentationAudioSession.activateIfNeeded(muted: true)
        PresentationAudioSession.reset()
    }

    @Test func resetClearsCachedActivation() {
        PresentationAudioSession.activateIfNeeded(muted: false)
        PresentationAudioSession.reset()
        // Re-activate after reset should succeed without throwing through the helper.
        PresentationAudioSession.activateIfNeeded(muted: false)
        PresentationAudioSession.reset()
    }
}
