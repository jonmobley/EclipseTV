//
//  SlideRemoveTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@MainActor
struct SlideRemoveTests {

    @Test func aSlideshowKeepsTwoSlides() {
        #expect(LibraryGridViewController.canRemoveSlide(fromSlideshowWith: 3))
        #expect(!LibraryGridViewController.canRemoveSlide(fromSlideshowWith: 2))
        #expect(!LibraryGridViewController.canRemoveSlide(fromSlideshowWith: 0))
    }

    @Test func theSlideOnScreenKeepsPlayingWhenAnotherIsRemoved() {
        let next = SlideshowPlaybackController.slideIndex(
            afterChangeTo: ["b", "c"], currentId: "c", currentIndex: 2
        )
        #expect(next.index == 1)
        #expect(!next.slideChanged)
    }

    @Test func removingTheSlideOnScreenShowsTheOneThatTookItsPlace() {
        let next = SlideshowPlaybackController.slideIndex(
            afterChangeTo: ["a", "c"], currentId: "b", currentIndex: 1
        )
        #expect(next.index == 1)
        #expect(next.slideChanged)
    }

    @Test func removingTheLastSlideOnScreenGoesBackToTheFirst() {
        let next = SlideshowPlaybackController.slideIndex(
            afterChangeTo: ["a", "b"], currentId: "c", currentIndex: 2
        )
        #expect(next.index == 0)
        #expect(next.slideChanged)
    }

    @Test func undoPutsTheSlideBackInOrderWithItsCover() throws {
        let suite = "SlideRemoveTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SlideshowStore(defaults: defaults)
        let made = try store.create(name: "Undo", showId: UUID(), itemIds: ["a", "b", "c"])
        store.setCover(itemId: "b", slideshowId: made.id)
        let before = try #require(store.slideshow(id: made.id))

        store.remove(itemId: "b", fromSlideshowId: made.id)
        #expect(store.slideshow(id: made.id)?.itemIds == ["a", "c"])

        store.reorder(itemIds: before.itemIds, inSlideshowId: made.id)
        store.setCover(itemId: "b", slideshowId: made.id)
        let after = try #require(store.slideshow(id: made.id))
        #expect(after.itemIds == ["a", "b", "c"])
        #expect(after.coverId == "b")
    }
}
