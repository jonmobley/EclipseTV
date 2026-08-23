//
//  AudioNowPlayingPresentationTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct AudioNowPlayingPresentationTests {

    @Test func landscapeSheetStaysEdgeAttachedAtMiniPlayerWidth() {
        let nav = AudioNowPlayingViewController.makeNavigation(onOpenLibrary: nil)
        let sheet = nav.sheetPresentationController
        #expect(sheet?.prefersEdgeAttachedInCompactHeight == true)
        #expect(sheet?.widthFollowsPreferredContentSizeWhenEdgeAttached == true)
        #expect(nav.preferredContentSize.width == AudioMiniPlayerView.compactWidth)
    }
}
