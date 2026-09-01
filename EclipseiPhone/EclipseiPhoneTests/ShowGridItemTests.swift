//
//  ShowGridItemTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowGridItemTests {

    @Test func mediaTilePinsItsLibraryId() {
        let item = LibraryItemDTO(
            id: "photo.jpg",
            name: "photo.jpg",
            isVideo: false,
            duration: 0,
            isAvailable: true
        )
        #expect(ShowGridItem.media(item).libraryThumbnailId == "photo.jpg")
    }

    @Test func toolAndAddTilesHaveNoLibraryThumbnail() {
        #expect(ShowGridItem.screensaver.libraryThumbnailId == nil)
        #expect(ShowGridItem.logo.libraryThumbnailId == nil)
        #expect(ShowGridItem.camera.libraryThumbnailId == nil)
        let poll = ShowLivePoll(
            showId: UUID(),
            pollId: "poll-1",
            title: "Session 1",
            questionCount: 3
        )
        #expect(ShowGridItem.livePoll(poll).libraryThumbnailId == nil)
        #expect(
            ShowGridItem.livePoll(poll).selectionId
                == ShowLivePollToken.token(for: poll.id)
        )
        let countdown = ShowCountdown(
            showId: UUID(), name: "Break", duration: 60
        )
        #expect(ShowGridItem.countdown(countdown).libraryThumbnailId == nil)
        #expect(ShowGridItem.add.libraryThumbnailId == nil)
    }

    @Test func slideshowPinsResolvedCoverWhenPresent() {
        let cover = "cover.jpg"
        let show = Slideshow(
            showId: UUID(),
            name: "Deck",
            itemIds: [cover],
            coverId: cover
        )
        #expect(ShowGridItem.slideshow(show).libraryThumbnailId == cover)
    }

    @Test func slideshowWithoutCoverHasNoLibraryThumbnail() {
        let show = Slideshow(showId: UUID(), name: "Empty")
        #expect(ShowGridItem.slideshow(show).libraryThumbnailId == nil)
    }
}
