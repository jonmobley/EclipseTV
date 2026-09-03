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
        #expect(bubble.musicButton.configuration?.baseBackgroundColor == UIColor.systemBlue)
        #expect(bubble.musicButton.configuration?.cornerStyle == .capsule)
        #expect(bubble.musicButton.accessibilityTraits.contains(.button))
        #expect(bubble.musicButton.accessibilityHint == "Choose something to play.")
        #expect(bubble.intrinsicContentSize.width == AudioMiniPlayerBubbleView.side)
    }

    @Test func idleHighlightScalesIn() {
        AudioPlayerController.shared.stop()
        #expect(AudioPlayerController.shared.hasActiveSession == false)
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        UIView.performWithoutAnimation {
            bubble.musicButton.isHighlighted = true
        }
        #expect(
            abs(bubble.musicButton.transform.a - AudioMiniPlayerBubbleView.idlePressScale)
                < 0.001
        )
        UIView.performWithoutAnimation {
            bubble.musicButton.isHighlighted = false
        }
        #expect(abs(bubble.musicButton.transform.a - 1) < 0.001)
    }

    @Test func playingShowsWaveformAsExpand() {
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applySessionChrome(active: true, playing: true)
        #expect(bubble.showsPlaybackWaveform)
        #expect(bubble.musicButton.accessibilityLabel == "Expand")
        #expect(bubble.musicButton.configuration?.image == nil)
        #expect(bubble.intrinsicContentSize.width == AudioMiniPlayerBubbleView.side)
    }

    @Test func expandedSessionShowsStop() {
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applySessionChrome(active: true, playing: true, expanded: true)
        #expect(bubble.showsPlaybackWaveform == false)
        #expect(bubble.musicButton.accessibilityLabel == "Stop")
        #expect(bubble.musicButton.configuration?.cornerStyle == .capsule)
        #expect(bubble.musicButton.configuration?.image != nil)
        #expect(bubble.musicButton.accessibilityHint == "Fades out and stops playback.")
    }

    @Test func pausedSessionShowsNoteNotStop() {
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applySessionChrome(active: true, playing: false)
        #expect(bubble.showsPlaybackWaveform == false)
        #expect(bubble.musicButton.accessibilityLabel == "Expand")
        #expect(bubble.musicButton.configuration?.image != nil)
    }

    @Test func drawerModeKeepsMusicLabelWithoutStop() {
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applySessionChrome(
            active: true, playing: true, expanded: true, togglesMusicPane: true
        )
        #expect(bubble.showsPlaybackWaveform)
        #expect(bubble.musicButton.accessibilityLabel == "Music")
        #expect(
            bubble.musicButton.accessibilityHint
                == "Shows or hides the Music pane."
        )
    }

    @Test func idleShowsNoteWithoutWaveform() {
        AudioPlayerController.shared.stop()
        let bubble = AudioMiniPlayerBubbleView(
            frame: CGRect(x: 0, y: 0, width: 72, height: 72)
        )
        bubble.applySessionChrome(active: false, playing: false)
        #expect(bubble.showsPlaybackWaveform == false)
        #expect(bubble.musicButton.configuration?.image != nil)
        #expect(bubble.musicButton.accessibilityLabel == "Music")
    }
}

@MainActor
struct AudioMiniPlayerWaveformTests {

    @Test func usesThreeBars() {
        let wave = AudioMiniPlayerWaveformView(
            frame: CGRect(x: 0, y: 0, width: 28, height: 26)
        )
        wave.layoutIfNeeded()
        #expect(wave.barCount == 3)
    }

    @Test func barsAnimateOnlyWhilePlaying() {
        let wave = AudioMiniPlayerWaveformView(
            frame: CGRect(x: 0, y: 0, width: 28, height: 26)
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
