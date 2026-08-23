//
//  AudioMiniPlayerBubbleTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct AudioMiniPlayerBubbleTests {

    @Test func idleControlIsAFilledButton() {
        AudioPlayerController.shared.stop()
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.reload()
        #expect(bubble.configuration?.baseBackgroundColor == UIColor.systemBlue)
        #expect(bubble.configuration?.cornerStyle == .capsule)
        #expect(bubble.accessibilityTraits.contains(.button))
        #expect(bubble.accessibilityHint == "Opens the Music page.")
    }

    @Test func idleHighlightScalesIn() {
        AudioPlayerController.shared.stop()
        #expect(AudioPlayerController.shared.hasActiveSession == false)
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        UIView.performWithoutAnimation {
            bubble.isHighlighted = true
        }
        #expect(abs(bubble.transform.a - AudioMiniPlayerBubbleView.idlePressScale) < 0.001)
        UIView.performWithoutAnimation {
            bubble.isHighlighted = false
        }
        #expect(abs(bubble.transform.a - 1) < 0.001)
    }

    @Test func playingShowsWaveformAndGlow() {
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applyPlaybackChrome(playing: true)
        #expect(bubble.showsPlaybackWaveform)
        #expect(bubble.configuration?.image == nil)
        #expect(bubble.isPlaybackGlowActive)
    }

    @Test func idleShowsNoteWithoutWaveform() {
        AudioPlayerController.shared.stop()
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applyPlaybackChrome(playing: false)
        #expect(bubble.showsPlaybackWaveform == false)
        #expect(bubble.configuration?.image != nil)
        #expect(bubble.isPlaybackGlowActive == false)
    }
}

@MainActor
struct AudioMiniPlayerWaveformTests {

    @Test func barsAnimateOnlyWhilePlaying() {
        let wave = AudioMiniPlayerWaveformView(
            frame: CGRect(x: 0, y: 0, width: 34, height: 30)
        )
        wave.layoutIfNeeded()
        wave.setPlaying(true)
        #expect(wave.isPlaying)
        #expect(wave.hasWaveAnimations)
        wave.setPlaying(false)
        #expect(wave.isPlaying == false)
        #expect(wave.hasWaveAnimations == false)
    }
}
