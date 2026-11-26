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

    /// Search sits left of Home on the tab row, and its field replaces the tabs
    /// while it is up, so the bar never grows.
    @Test func searchFieldTakesTheTabRowsPlace() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.showsTabStrip = true
        bar.setTabPage(.library)
        bar.layoutIfNeeded()
        let search = bar.firstDescendant(label: "Search")
        let home = bar.firstDescendant(identifier: HomeTab.home.accessibilityIdentifier)
        let searchFrame = search.map { bar.convert($0.bounds, from: $0) } ?? .null
        let homeFrame = home.map { bar.convert($0.bounds, from: $0) } ?? .null
        #expect(searchFrame.maxX <= homeFrame.minX)
        #expect(abs(searchFrame.midY - homeFrame.midY) < 2)

        bar.beginSearch(placeholder: "Search Library")
        bar.layoutIfNeeded()
        #expect(bar.tabStrip.isHidden)
        let field = bar.convert(bar.searchField.bounds, from: bar.searchField)
        #expect(abs(field.midY - homeFrame.midY) < 2)
        bar.endSearch()
        #expect(!bar.tabStrip.isHidden)
    }

    @Test func eachPageShowsItsOwnControls() {
        let bar = HomeHeaderBar(frame: CGRect(x: 0, y: 0, width: 390, height: 90))
        bar.showsTabStrip = true
        let search = bar.firstDescendant(label: "Search")
        let addMusic = bar.firstDescendant(label: "Add Music")
        let newShow = bar.firstDescendant(label: "New Show")
        let addLibrary = bar.firstDescendant(label: "Add to Library")
        let searchOn = { (search as? UIControl)?.isEnabled == true && search?.isHidden == false }
        // Home has nothing to search: the icon keeps its place, dimmed.
        #expect(search?.isHidden == false)
        #expect(!searchOn())
        #expect(newShow?.isHidden == false)

        bar.setTabPage(.library)
        #expect(searchOn())
        #expect(addMusic?.isHidden == true)
        #expect(newShow?.isHidden == true)
        // Library has its own "+", which imports into the Library only.
        #expect(addLibrary?.isHidden == false)

        bar.setTabPage(.music)
        #expect(addLibrary?.isHidden == true)
        #expect(searchOn())
        #expect(addMusic?.isHidden == false)
        // Inside a playlist the playlist's own bar takes over.
        bar.setMusicAddAvailable(false)
        #expect(addMusic?.isHidden == true)
        #expect(!searchOn())

        // The Show page: only once a Show is open.
        bar.setTabPage(.show)
        #expect(!searchOn())
        bar.setShowModeChrome(true)
        #expect(searchOn())
        bar.setArranging(true)
        #expect(!searchOn())
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
        #expect(search?.alpha == 0)
        #expect(bar.searchField.placeholder == "Search Library")
        bar.searchField.text = "fl"
        bar.searchField.sendActions(for: .editingChanged)
        #expect(typed == ["fl"])
        bar.endSearch()
        #expect(!bar.isSearching)
        #expect(bar.searchField.text == "")
        #expect(search?.alpha == 1)
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
