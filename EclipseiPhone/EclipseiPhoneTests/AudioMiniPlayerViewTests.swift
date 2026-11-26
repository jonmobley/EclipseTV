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

    /// Landscape has room for the full card; portrait runs it edge to edge
    /// (inside the side insets), with the Music circle nested in its corner.
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
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 390, height: AudioMiniPlayerView.preferredHeight)
        )
        let fill = bar.subviews.first {
            $0.backgroundColor == AudioMiniPlayerView.barBackgroundColor
        }
        #expect(fill != nil)
        #expect(bar.backgroundColor == .clear)
    }

    /// The circle is as tall as the button row and sits wholly inside the card.
    @Test func cardMatesWithTheMusicCircle() {
        #expect(AudioMiniPlayerBubbleView.side == AudioMiniPlayerView.controlRowHeight)
        #expect(AudioMiniPlayerView.connectedOverlap == AudioMiniPlayerBubbleView.side)
        #expect(
            AudioMiniPlayerView.preferredHeight
                == AudioMiniPlayerView.controlRowHeight + AudioMiniPlayerView.titleRowHeight
        )
    }

    /// Rounded on all four corners, tighter on top than at the button row.
    @Test func cardOutlineRoundsEveryCorner() {
        let rect = CGRect(x: 0, y: 0, width: 300, height: 108)
        let path = AudioMiniPlayerShape.maskPath(in: rect, topRadius: 26, bottomRadius: 32)
        #expect(path.contains(CGPoint(x: 150, y: 54)))
        #expect(path.contains(CGPoint(x: 150, y: 1)))
        #expect(path.contains(CGPoint(x: 299, y: 54)))
        for corner in [
            CGPoint(x: 1, y: 1), CGPoint(x: 299, y: 1),
            CGPoint(x: 1, y: 107), CGPoint(x: 299, y: 107)
        ] {
            #expect(!path.contains(corner))
        }
        // The bottom corners cut deeper than the top ones.
        #expect(path.contains(CGPoint(x: 8, y: 8)))
        #expect(!path.contains(CGPoint(x: 8, y: 100)))
        // A rect too small for the radii still yields a closed shape.
        let tiny = AudioMiniPlayerShape.maskPath(
            in: CGRect(x: 0, y: 0, width: 20, height: 0), topRadius: 26, bottomRadius: 32
        )
        #expect(!tiny.contains(CGPoint(x: 10, y: 5)))
    }

    /// Mic, Pause, Stop, Next, in that order (owner's call, 2026-11-25).
    @Test func controlsRunMicPauseStopNext() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 361, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.applyPlaybackChrome(playing: true, hasNextSong: true)
        bar.layoutIfNeeded()
        #expect(
            bar.controlButtons.map(\.accessibilityLabel)
                == ["Duck volume", "Pause", "Stop", "Next song"]
        )
        let frames = bar.controlButtons.map { $0.convert($0.bounds, to: bar) }
        for frame in frames {
            #expect(abs(frame.width - AudioMiniPlayerView.controlSide) < 0.01)
            #expect(abs(frame.height - AudioMiniPlayerView.controlSide) < 0.01)
            #expect(frame.minY >= AudioMiniPlayerView.titleRowHeight)
        }
        #expect(zip(frames, frames.dropFirst()).allSatisfy { $0.maxX < $1.minX })
        // Next sits as far from the Music circle as the buttons sit from each other.
        let circleEdge = 361 - AudioMiniPlayerBubbleView.side
        #expect(abs((circleEdge - frames[3].maxX) - (frames[1].minX - frames[0].maxX)) < 0.01)
        #expect((frames.last?.maxX ?? .infinity) <= 361 - AudioMiniPlayerBubbleView.side)
    }

    @Test func pauseButtonFollowsPlayback() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 361, height: AudioMiniPlayerView.preferredHeight)
        )
        let playPause = bar.controlButtons[1]
        let next = bar.controlButtons[3]
        bar.applyPlaybackChrome(playing: true, hasNextSong: true)
        #expect(playPause.accessibilityLabel == "Pause")
        #expect(next.isEnabled)
        bar.applyPlaybackChrome(playing: false, hasNextSong: false)
        #expect(playPause.accessibilityLabel == "Play")
        #expect(next.isEnabled == false)
    }

    /// A very narrow window shrinks the four buttons evenly; none is clipped.
    @Test func controlsShrinkToFitANarrowCard() {
        let width: CGFloat = 270
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: width, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.layoutIfNeeded()
        let frames = bar.controlButtons.map { $0.convert($0.bounds, to: bar) }
        #expect(frames.count == 4)
        #expect(frames.allSatisfy { $0.width < AudioMiniPlayerView.controlSide && $0.width > 40 })
        // Equal to within a pixel: the frames are rounded to the screen's grid.
        #expect(frames.allSatisfy { abs($0.width - frames[0].width) < 1 })
        #expect((frames.first?.minX ?? -1) >= 0)
        #expect((frames.last?.maxX ?? .infinity) <= width - AudioMiniPlayerBubbleView.side)
    }

    @Test func barUsesDuckAndStop() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 360, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.layoutIfNeeded()
        let buttons = bar.controlButtons
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
                == AudioMiniPlayerView.controlRowHeight
                - AudioMiniPlayerView.controlChromeInset * 2
        )
    }

    /// The song name has the card's full width on one line, above the buttons.
    @Test func longSongNameStaysOnOneLineAboveTheButtons() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 300, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.showTrack(title: "Remember the Name (feat. Styles of Beyond)", details: "Fort Minor")
        bar.layoutIfNeeded()
        #expect(bar.titleLineCount == 1)
        #expect(bar.spokenTrack == "Remember the Name (feat. Styles of Beyond), Fort Minor")
        #expect(bar.isAccessibilityElement == false)
    }
}
