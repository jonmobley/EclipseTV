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
}
