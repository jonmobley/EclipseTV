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

    @Test func searchFieldAddsARowUnderTheTabs() {
        #expect(
            HomeHeaderBar.height(
                showsTabStrip: true, verticalSizeClass: .regular, isSearching: true
            ) == 138
        )
        #expect(
            HomeHeaderBar.height(
                showsTabStrip: true, verticalSizeClass: .compact, isSearching: true
            ) == 100
        )
    }

    @Test func eachPageShowsItsOwnControls() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.showsTabStrip = true
        let search = bar.firstDescendant(label: "Search")
        let addMusic = bar.firstDescendant(label: "Add Music")
        let newShow = bar.firstDescendant(label: "New Show")
        // Home has nothing to search.
        #expect(search?.isHidden == true)
        #expect(newShow?.isHidden == false)

        bar.setTabPage(.library)
        #expect(search?.isHidden == false)
        #expect(addMusic?.isHidden == true)
        #expect(newShow?.isHidden == true)

        bar.setTabPage(.music)
        #expect(search?.isHidden == false)
        #expect(addMusic?.isHidden == false)
        // Inside a playlist the playlist's own bar takes over.
        bar.setMusicAddAvailable(false)
        #expect(addMusic?.isHidden == true)
        #expect(search?.isHidden == true)

        // The Show page: only once a Show is open.
        bar.setTabPage(.show)
        #expect(search?.isHidden == true)
        bar.setShowModeChrome(true)
        #expect(search?.isHidden == false)
        bar.setArranging(true)
        #expect(search?.isHidden == true)
    }

    /// Camera left the tab row for a round button in the bottom-leading corner.
    @Test func tabRowHasOnlyTheFourPages() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.showsTabStrip = true
        #expect(bar.tabStrip.firstDescendant(identifier: "home.tab.camera") == nil)
        #expect(HomeTab.allCases.count == 4)
        bar.tabStrip.setPosition(3)
        #expect(bar.tabStrip.selected == .music)
    }

    /// The Camera button gives way to the music card only when the card would
    /// reach it, and always while arranging, selecting or searching.
    @Test func cameraButtonStepsAsideOnlyWhenCovered() {
        let button = CGRect(x: 16, y: 800, width: 56, height: 56)
        // Upright phone: the card spans the width and reaches the button.
        let wideCard = CGRect(x: 20, y: 790, width: 360, height: 76)
        #expect(HomeCameraButton.shouldHide(
            cardFrame: wideCard, buttonFrame: button, isEditing: false, isSearching: false
        ))
        // Sideways phone or wider window: the card stops well short of it.
        let shortCard = CGRect(x: 400, y: 300, width: 360, height: 76)
        #expect(!HomeCameraButton.shouldHide(
            cardFrame: shortCard, buttonFrame: button, isEditing: false, isSearching: false
        ))
        #expect(!HomeCameraButton.shouldHide(
            cardFrame: nil, buttonFrame: button, isEditing: false, isSearching: false
        ))
        #expect(HomeCameraButton.shouldHide(
            cardFrame: nil, buttonFrame: button, isEditing: true, isSearching: false
        ))
        #expect(HomeCameraButton.shouldHide(
            cardFrame: nil, buttonFrame: button, isEditing: false, isSearching: true
        ))
    }

    @Test func searchButtonHidesWhileItsFieldIsUp() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 138))
        bar.showsTabStrip = true
        bar.setTabPage(.library)
        let search = bar.firstDescendant(label: "Search")
        var typed: [String] = []
        bar.onSearchTextChanged = { typed.append($0) }
        bar.beginSearch(placeholder: "Search Library")
        #expect(bar.isSearching)
        #expect(search?.isHidden == true)
        #expect(bar.searchField.placeholder == "Search Library")
        bar.searchField.text = "fl"
        bar.searchField.sendActions(for: .editingChanged)
        #expect(typed == ["fl"])
        bar.endSearch()
        #expect(!bar.isSearching)
        #expect(bar.searchField.text == "")
        #expect(search?.isHidden == false)
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
