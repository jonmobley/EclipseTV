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

@MainActor
struct AudioLibraryPickerPresentationTests {

    @Test func pickerSheetMatchesNowPlayingChrome() {
        let nav = AudioLibraryViewController.makePickerNavigation(onAddMusic: nil)
        let sheet = nav.sheetPresentationController
        #expect(sheet?.prefersEdgeAttachedInCompactHeight == true)
        #expect(sheet?.widthFollowsPreferredContentSizeWhenEdgeAttached == true)
        #expect(sheet?.prefersGrabberVisible == true)
        #expect(sheet?.detents.count == 2)
        #expect(nav.preferredContentSize.width == AudioMiniPlayerView.compactWidth)
        #expect(nav.viewControllers.first is AudioLibraryViewController)
    }
}
