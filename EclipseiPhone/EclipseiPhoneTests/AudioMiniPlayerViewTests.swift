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

    @Test func compactCardOnIPadAndPhoneLandscape() {
        #expect(
            AudioMiniPlayerView.usesCompactCard(
                verticalSizeClass: .regular,
                horizontalSizeClass: .regular
            )
        )
        #expect(
            AudioMiniPlayerView.usesCompactCard(
                verticalSizeClass: .compact,
                horizontalSizeClass: .compact
            )
        )
        #expect(
            AudioMiniPlayerView.usesCompactCard(
                verticalSizeClass: .compact,
                horizontalSizeClass: .regular
            )
        )
        #expect(
            AudioMiniPlayerView.usesCompactCard(
                verticalSizeClass: .regular,
                horizontalSizeClass: .compact
            ) == false
        )
    }

    @Test func portraitBarCoversHomeIndicator() {
        let homeIndicator: CGFloat = 34
        #expect(
            AudioMiniPlayerView.barHeight(floating: false, safeAreaBottom: homeIndicator)
                == AudioMiniPlayerView.preferredHeight + homeIndicator
        )
        #expect(
            AudioMiniPlayerView.barHeight(floating: true, safeAreaBottom: homeIndicator)
                == AudioMiniPlayerView.preferredHeight
        )
        #expect(
            AudioMiniPlayerView.barHeight(floating: false, safeAreaBottom: 0)
                == AudioMiniPlayerView.preferredHeight
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

    @Test func portraitReservesTrailingSpaceForCircle() {
        #expect(
            AudioMiniPlayerView.minimizeTrailingInset(floating: false)
                == AudioMiniPlayerBubbleView.side
                + AudioMiniPlayerView.circleFooterGap
                + AudioMiniPlayerView.compactTrailingInset
        )
        #expect(
            AudioMiniPlayerView.minimizeTrailingInset(floating: true)
                == AudioMiniPlayerView.controlTrailingInset
        )
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
