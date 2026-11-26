//
//  HomeTabPagingTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct HomeTabPagingTests {

    @Test func pagesRunHomeLibraryShowMusic() {
        #expect(HomeTab.allCases == [.home, .library, .show, .music])
        #expect(HomeTab.allCases.map(\.title) == ["Home", "Library", "Show", "Music"])
    }

    @Test func gridSlotInViewFollowsThePagerPosition() {
        // Anywhere left of Library shows the Home slot.
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 0) == .home)
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 0.97) == .home)
        // Resting on Library or Music shows neither slot, so nothing changes mode.
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 1) == nil)
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 3) == nil)
        // Either side of the Show page shows the Show slot.
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 1.03) == .show)
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 2) == .show)
        #expect(HomeTabPaging.visibleGridSlot(atPosition: 2.9) == .show)
    }

    @Test func nearestTabRoundsAndStaysInRange() {
        #expect(HomeTabPaging.nearestTab(toPosition: -0.4) == .home)
        #expect(HomeTabPaging.nearestTab(toPosition: 0.49) == .home)
        #expect(HomeTabPaging.nearestTab(toPosition: 0.51) == .library)
        #expect(HomeTabPaging.nearestTab(toPosition: 2.2) == .show)
        #expect(HomeTabPaging.nearestTab(toPosition: 9) == .music)
    }

    @Test func onlyNeighboursSlide() {
        #expect(HomeTabPaging.slides(from: .library, to: .show))
        #expect(HomeTabPaging.slides(from: .music, to: .show))
        #expect(!HomeTabPaging.slides(from: .home, to: .show))
        #expect(!HomeTabPaging.slides(from: .home, to: .music))
        #expect(!HomeTabPaging.slides(from: .show, to: .show))
    }

    @Test func showTabReopensTheLastShowOfTheCurrentMode() {
        let landscape: (String) -> Bool = { $0.hasPrefix("L") }
        // The last open Show wins over a more recent one.
        #expect(
            HomeTabPaging.showToOpen(
                lastOpen: "L2", recents: ["L1", "L2"], isCurrentMode: landscape
            ) == "L2"
        )
        // A last Show from the other Display Mode is skipped: a swipe never
        // changes the screen's shape.
        #expect(
            HomeTabPaging.showToOpen(
                lastOpen: "V1", recents: ["V1", "L1"], isCurrentMode: landscape
            ) == "L1"
        )
        #expect(
            HomeTabPaging.showToOpen(
                lastOpen: nil, recents: ["V1"], isCurrentMode: landscape
            ) == nil
        )
    }
}

@MainActor
struct HomeTabStripViewTests {

    private func makeStrip() -> HomeTabStripView {
        let strip = HomeTabStripView(frame: CGRect(x: 0, y: 0, width: 360, height: 38))
        strip.layoutIfNeeded()
        return strip
    }

    @Test func lineSitsUnderTheSelectedTab() {
        let strip = makeStrip()
        let home = strip.indicatorFrame(forPosition: 0)
        let music = strip.indicatorFrame(forPosition: 3)
        #expect(home.width > 0)
        #expect(music.minX > home.maxX)
        // Half-way through a swipe the line is between the two tabs.
        let between = strip.indicatorFrame(forPosition: 0.5)
        let library = strip.indicatorFrame(forPosition: 1)
        #expect(between.minX > home.minX)
        #expect(between.minX < library.minX)
    }

    @Test func swipePositionSelectsTheNearestTab() {
        let strip = makeStrip()
        strip.setPosition(1.6)
        #expect(strip.selected == .show)
        strip.setPosition(40)
        #expect(strip.selected == .music)
        strip.setSelected(.home, animated: false)
        #expect(strip.selected == .home)
    }

    @Test func tappingATabReportsIt() {
        let strip = makeStrip()
        var tapped: HomeTab?
        strip.onSelect = { tapped = $0 }
        let button = strip.firstDescendant(identifier: HomeTab.library.accessibilityIdentifier)
            as? UIButton
        button?.sendActions(for: .touchUpInside)
        #expect(tapped == .library)
    }
}

@MainActor
struct HomeHeaderBarTabStripTests {

    @Test func heightAddsTheTabsOnlyWhenTheySitUnderTheRow() {
        #expect(HomeHeaderBar.height(showsTabStrip: false, verticalSizeClass: .regular) == 52)
        #expect(HomeHeaderBar.height(showsTabStrip: true, verticalSizeClass: .regular) == 90)
        // Phone landscape: the tabs go inside the row.
        #expect(HomeHeaderBar.height(showsTabStrip: true, verticalSizeClass: .compact) == 52)
    }

    @Test func libraryAndMusicPagesDropHomeAndShowControls() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.showsTabStrip = true
        let addMusic = bar.firstDescendant(label: "Add Music")
        let newShow = bar.firstDescendant(label: "New Show")
        #expect(newShow?.isHidden == false)

        bar.setTabPage(.library)
        #expect(addMusic?.isHidden == true)
        #expect(newShow?.isHidden == true)

        bar.setTabPage(.music)
        #expect(addMusic?.isHidden == false)
        // Inside a playlist the playlist's own bar has the "+".
        bar.setMusicAddAvailable(false)
        #expect(addMusic?.isHidden == true)
    }

    @Test func backChevronGivesWayToTheHomeTab() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.destinationTabsOverride = false
        bar.setShowModeChrome(true)
        let back = bar.firstDescendant(label: "Back")
        #expect(back?.isHidden == false)
        bar.showsTabStrip = true
        #expect(back?.isHidden == true)
    }
}

@MainActor
struct HomeFooterBarTests {

    @Test func homeShowsCameraAloneAndSearchablePagesAddSearch() {
        let bar = HomeFooterBar(frame: CGRect(x: 0, y: 0, width: 300, height: 56))
        let camera = bar.firstDescendant(label: "Camera")
        let search = bar.firstDescendant(label: "Search")
        #expect(camera?.isHidden == false)
        #expect(search?.isHidden == true)
        // The field only appears once Search is tapped.
        #expect(bar.searchField.isHidden)

        bar.setSearch(placeholder: "Search Music")
        #expect(search?.isHidden == false)
        #expect(bar.searchField.isHidden)
        #expect(bar.searchField.placeholder == "Search Music")
    }

    @Test func searchingTurnsTheBarIntoTheFieldAndBackOnEnd() {
        let bar = HomeFooterBar(frame: CGRect(x: 0, y: 0, width: 300, height: 56))
        bar.setSearch(placeholder: "Search Library")
        var typed: [String] = []
        var cancelled = 0
        bar.onSearchTextChanged = { typed.append($0) }
        bar.onCancelSearch = { cancelled += 1 }

        bar.setSearching(true)
        let cancel = bar.firstDescendant(label: "Cancel search") as? UIButton
        #expect(!bar.searchField.isHidden)
        #expect(bar.firstDescendant(label: "Camera")?.superview?.isHidden == true)
        bar.searchField.text = "fl"
        bar.searchField.sendActions(for: .editingChanged)
        #expect(typed == ["fl"])
        cancel?.sendActions(for: .touchUpInside)
        #expect(cancelled == 1)

        bar.setSearching(false)
        #expect(bar.searchField.text == "")
        #expect(bar.searchField.isHidden)
        #expect(bar.firstDescendant(label: "Camera")?.superview?.isHidden == false)
    }

    @Test func cameraButtonOpensTheCamera() {
        let bar = HomeFooterBar(frame: CGRect(x: 0, y: 0, width: 300, height: 56))
        var opened = 0
        bar.onOpenCamera = { opened += 1 }
        (bar.firstDescendant(label: "Camera") as? UIButton)?
            .sendActions(for: .touchUpInside)
        #expect(opened == 1)
    }

    @Test func aSearchKeepsTheBarUpWhileScrolling() {
        let bar = HomeFooterBar(frame: CGRect(x: 0, y: 0, width: 300, height: 56))
        bar.setScrolledAway(true, animated: false)
        #expect(bar.isScrolledAway)
        bar.setScrolledAway(false, animated: false)
        bar.setSearch(placeholder: "Search this Show")
        bar.setSearching(true)
        bar.setScrolledAway(true, animated: false)
        #expect(!bar.isScrolledAway)
    }

    @Test func barHidesGoingDownAndReturnsGoingUpOrAtTheTop() {
        #expect(HomeFooterScroll.shouldHide(delta: 12, distanceFromTop: 300) == true)
        #expect(HomeFooterScroll.shouldHide(delta: -12, distanceFromTop: 300) == false)
        // Tiny movements change nothing.
        #expect(HomeFooterScroll.shouldHide(delta: 1, distanceFromTop: 300) == nil)
        // At the top it is always there.
        #expect(HomeFooterScroll.shouldHide(delta: 12, distanceFromTop: 2) == false)
    }
}

struct ShowGridItemSearchTests {

    @Test func cardsAreFoundByNameInAnyCase() {
        let page = WebPage(title: "Welcome Slides", url: URL(string: "https://example.org/a")!)
        let site = ShowGridItem.website(page)
        #expect(site.matchesSearch("welcome"))
        #expect(site.matchesSearch("  SLIDES "))
        // The address counts too.
        #expect(site.matchesSearch("example.org"))
        #expect(!site.matchesSearch("countdown"))
    }

    @Test func toolTilesAreFoundByWhatTheyAreCalled() {
        #expect(ShowGridItem.camera.matchesSearch("cam"))
        #expect(ShowGridItem.logo.matchesSearch("background"))
        #expect(ShowGridItem.screensaver.matchesSearch("screen"))
        #expect(!ShowGridItem.camera.matchesSearch("background"))
    }

    @Test func addTileNeverMatchesAndAnEmptySearchMatchesEverything() {
        #expect(!ShowGridItem.add.matchesSearch("a"))
        #expect(ShowGridItem.add.matchesSearch("  "))
        #expect(ShowGridItem.pdf(SavedPDF(title: "Résumé")).matchesSearch("resume"))
    }
}

private extension UIView {
    func firstDescendant(identifier: String) -> UIView? {
        for view in subviews {
            if view.accessibilityIdentifier == identifier { return view }
            if let found = view.firstDescendant(identifier: identifier) { return found }
        }
        return nil
    }

    func firstDescendant(label: String) -> UIView? {
        for view in subviews {
            if view.accessibilityLabel == label { return view }
            if let found = view.firstDescendant(label: label) { return found }
        }
        return nil
    }
}
