//
//  AudioMiniPlayerViewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct AudioMiniPlayerViewTests {

    /// Landscape has room for the full card; portrait squeezes it to fit the
    /// Music circle rather than falling back to a full-width footer.
    @Test func cardWidthLeavesRoomForTheMusicCircle() {
        let reserved = AudioMiniPlayerView.compactTrailingInset * 2
            + AudioMiniPlayerBubbleView.side
            - AudioMiniPlayerView.connectedOverlap

        #expect(
            AudioMiniPlayerView.cardWidth(containerWidth: 852, horizontalSafeArea: 118)
                == AudioMiniPlayerView.compactWidth + AudioMiniPlayerView.connectedOverlap
        )

        let portrait = AudioMiniPlayerView.cardWidth(
            containerWidth: 393, horizontalSafeArea: 0
        )
        #expect(portrait == 393 - reserved)
        #expect(portrait < AudioMiniPlayerView.compactWidth + AudioMiniPlayerView.connectedOverlap)
    }

    /// Auto Layout reports a zero-width container during early layout, and
    /// `NSLayoutConstraint` needs a positive width.
    @Test func cardWidthFloorsAtTheMinimum() {
        #expect(
            AudioMiniPlayerView.cardWidth(containerWidth: 0, horizontalSafeArea: 0)
                == AudioMiniPlayerView.minimumCompactWidth
        )
        #expect(
            AudioMiniPlayerView.cardWidth(containerWidth: 320, horizontalSafeArea: 0)
                >= AudioMiniPlayerView.minimumCompactWidth
        )
    }

    @Test func barFillMatchesPlayerBackground() {
        let bar = AudioMiniPlayerView(frame: CGRect(x: 0, y: 0, width: 390, height: 64))
        let fill = bar.subviews.first {
            $0.backgroundColor == AudioMiniPlayerView.barBackgroundColor
        }
        #expect(fill != nil)
        #expect(bar.backgroundColor == .clear)
    }

    @Test func cardMatesWithTheMusicCircle() {
        #expect(AudioMiniPlayerBubbleView.side == AudioMiniPlayerView.preferredHeight)
        #expect(AudioMiniPlayerView.connectedOverlap == AudioMiniPlayerView.preferredHeight / 2)
        let rect = CGRect(x: 0, y: 0, width: 200, height: 64)
        let path = AudioMiniPlayerShape.maskPath(in: rect, biteOnRight: true)
        #expect(path.contains(CGPoint(x: 8, y: 32)))
        #expect(path.contains(CGPoint(x: 150, y: 32)))
        #expect(!path.contains(CGPoint(x: 0, y: 0)))
        #expect(!path.contains(CGPoint(x: 190, y: 32)))
        #expect(!path.contains(CGPoint(x: 199, y: 1)))
    }

    @Test func mirroredCardBitesTheLeadingEdge() {
        let path = AudioMiniPlayerShape.maskPath(
            in: CGRect(x: 0, y: 0, width: 200, height: 64),
            biteOnRight: false
        )
        #expect(!path.contains(CGPoint(x: 10, y: 32)))
        #expect(path.contains(CGPoint(x: 50, y: 32)))
        #expect(path.contains(CGPoint(x: 190, y: 32)))
        #expect(!path.contains(CGPoint(x: 199, y: 1)))
    }

    @Test func barUsesDuckAndStop() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 360, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.layoutIfNeeded()
        let buttons = bar.subviews.compactMap { $0 as? UIButton }
        let duck = buttons.first { $0.accessibilityLabel == "Duck volume" }
        let stop = buttons.first { $0.accessibilityLabel == "Stop" }
        #expect(duck != nil)
        #expect(stop?.accessibilityHint == "Fades out and stops playback.")
        bar.applyDuckChrome(ducked: true)
        #expect(duck?.accessibilityValue == "On")
        #expect(duck?.configuration?.background.backgroundColor == UIColor.accent)
        bar.applyDuckChrome(ducked: false)
        #expect(duck?.accessibilityValue == "Off")
    }

    @Test func micDuckLowersPlaybackVolume() {
        let player = AudioPlayerController.shared
        let wasDucked = player.isDucked
        defer { player.setDucked(wasDucked) }
        player.setDucked(false)
        #expect(player.playbackVolume == player.volume)
        player.setDucked(true)
        #expect(player.isDucked)
        #expect(player.playbackVolume == min(player.volume, AudioPlayerController.duckedVolume))
        player.setDucked(false)
        #expect(player.isDucked == false)
        #expect(player.playbackVolume == player.volume)
    }

    @Test func cardChromeIsShadowed() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 360, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.layoutIfNeeded()
        #expect(bar.layer.shadowOpacity > 0)
        #expect(bar.layer.shadowPath != nil)
        #expect(bar.clipsToBounds == false)
    }

    @Test func chromeControlsFillBarHeight() {
        #expect(
            AudioMiniPlayerView.controlSide
                == AudioMiniPlayerView.preferredHeight
                - AudioMiniPlayerView.controlChromeInset * 2
        )
        #expect(
            AudioMiniPlayerView.controlTrailingInset
                == AudioMiniPlayerView.connectedOverlap + AudioMiniPlayerView.controlChromeInset
        )
    }
}
