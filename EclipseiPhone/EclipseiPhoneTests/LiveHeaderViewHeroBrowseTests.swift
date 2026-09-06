//
//  LiveHeaderViewHeroBrowseTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewHeroBrowseTests {

    @Test func heroInstallsOneSwipePairForBothBrowseModes() {
        let header = makeHeader()
        #expect(header.browseSwipeRecognizers.count == 2)
        #expect(header.browseSwipeRecognizers.contains { $0.direction == .left })
        #expect(header.browseSwipeRecognizers.contains { $0.direction == .right })
    }

    @Test func runningSlideshowKeepsTheSwipe() {
        let header = makeHeader()
        header.allowsSlideshowBrowse = true
        header.allowsLibraryBrowse = true
        var slides = 0
        var stills = 0
        header.onSlideshowSwipe = { _ in slides += 1 }
        header.onLibraryBrowse = { _ in stills += 1 }

        header.dispatchHeroBrowse(delta: 1)
        #expect(slides == 1)
        #expect(stills == 0)
    }

    @Test func stillsBrowseOnlyWhenNoSlideshowIsLive() {
        let header = makeHeader()
        header.allowsLibraryBrowse = true
        var deltas: [Int] = []
        header.onLibraryBrowse = { deltas.append($0) }

        header.dispatchHeroBrowse(delta: 1)
        header.dispatchHeroBrowse(delta: -1)
        #expect(deltas == [1, -1])
    }

    @Test func swipeIsInertWhenBrowseIsDisabled() {
        let header = makeHeader()
        var calls = 0
        header.onLibraryBrowse = { _ in calls += 1 }
        header.onSlideshowSwipe = { _ in calls += 1 }

        header.dispatchHeroBrowse(delta: 1)
        #expect(calls == 0)
        #expect(header.isUserInteractionEnabled == false)
    }

    @Test func browsableStillMakesTheHeroInteractive() {
        let header = makeHeader()
        header.allowsLibraryBrowse = true
        #expect(header.isUserInteractionEnabled == true)

        header.allowsLibraryBrowse = false
        #expect(header.isUserInteractionEnabled == false)
    }

    // MARK: - Helpers

    private func makeHeader() -> LiveHeaderView {
        LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    }
}
