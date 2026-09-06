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

    /// Landscape has room for the full card; portrait squeezes it to fit beside
    /// the Music circle rather than falling back to a full-width footer.
    @Test func cardWidthLeavesRoomForTheMusicCircle() {
        let reserved = AudioMiniPlayerView.compactTrailingInset * 2
            + AudioMiniPlayerBubbleView.side
            + AudioMiniPlayerView.circleFooterGap

        #expect(
            AudioMiniPlayerView.cardWidth(containerWidth: 852, horizontalSafeArea: 118)
                == AudioMiniPlayerView.compactWidth
        )

        let portrait = AudioMiniPlayerView.cardWidth(
            containerWidth: 393, horizontalSafeArea: 0
        )
        #expect(portrait == 393 - reserved)
        #expect(portrait < AudioMiniPlayerView.compactWidth)
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
        let bar = AudioMiniPlayerView(frame: CGRect(x: 0, y: 0, width: 390, height: 98))
        #expect(bar.isOpaque)
        #expect(bar.backgroundColor == UIColor.secondarySystemBackground)
    }

    @Test func volumeSliderStartsClosed() {
        let bar = AudioMiniPlayerView(frame: CGRect(x: 0, y: 0, width: 390, height: 98))
        bar.layoutIfNeeded()
        #expect(bar.isVolumeExpanded == false)
        bar.collapseVolumeControl()
        #expect(bar.isVolumeExpanded == false)
    }

    @Test func volumeControlOpensOnDemand() {
        let side = AudioMiniVolumeControl.buttonSide
        let control = AudioMiniVolumeControl(
            frame: CGRect(x: 0, y: 0, width: side, height: side)
        )
        control.layoutIfNeeded()
        #expect(control.isExpanded == false)
        control.setExpanded(true, animated: false)
        #expect(control.isExpanded == true)
        control.setExpanded(false, animated: false)
        #expect(control.isExpanded == false)
    }

    @Test func volumePercentTextClamps() {
        #expect(AudioMiniVolumeControl.percentText(for: 0) == "0%")
        #expect(AudioMiniVolumeControl.percentText(for: 0.4) == "40%")
        #expect(AudioMiniVolumeControl.percentText(for: 0.75) == "75%")
        #expect(AudioMiniVolumeControl.percentText(for: 1) == "100%")
        #expect(AudioMiniVolumeControl.percentText(for: -0.2) == "0%")
        #expect(AudioMiniVolumeControl.percentText(for: 1.4) == "100%")
    }

    @Test func volumeReadoutAppearsWhileDragging() {
        let side = AudioMiniVolumeControl.buttonSide
        let control = AudioMiniVolumeControl(
            frame: CGRect(x: 0, y: 0, width: side, height: side)
        )
        var last: (Float, Bool)?
        control.onVolumeChange = { last = ($0, $1) }
        control.setExpanded(true, animated: false)
        #expect(control.isReadoutVisible == false)

        control.applyDragVolume(0.4)
        #expect(control.isReadoutVisible)
        #expect(last?.0 == 0.4)
        #expect(last?.1 == false)

        control.finishDragVolume()
        #expect(control.isReadoutVisible)
        #expect(last?.1 == true)

        control.setExpanded(false, animated: false)
        #expect(control.isReadoutVisible == false)
    }

    @Test func cardChromeIsRoundedAndShadowed() {
        let bar = AudioMiniPlayerView(
            frame: CGRect(x: 0, y: 0, width: 360, height: AudioMiniPlayerView.preferredHeight)
        )
        bar.layoutIfNeeded()
        #expect(bar.layer.cornerRadius == AudioMiniPlayerView.compactCornerRadius)
        #expect(bar.layer.shadowOpacity > 0)
        // Volume slider opens above the card, so it must not be clipped.
        #expect(bar.clipsToBounds == false)
    }

    @Test func chromeControlsFillBarHeight() {
        #expect(
            AudioMiniPlayerView.controlSide
                == AudioMiniPlayerView.preferredHeight
                - AudioMiniPlayerView.controlChromeInset * 2
        )
        #expect(AudioMiniVolumeControl.buttonSide == AudioMiniPlayerView.controlSide)
    }
}
