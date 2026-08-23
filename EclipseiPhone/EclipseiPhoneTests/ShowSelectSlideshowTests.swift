//
//  ShowSelectSlideshowTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowSelectSlideshowTests {

    @Test func imagesInGridOrder() {
        let items: [ShowGridItem] = [
            .camera,
            .media(makeItem(id: "b")),
            .media(makeItem(id: "a")),
            .add
        ]
        let ids = ShowSelectSlideshow.imageIds(
            selectedIds: ["a", "b"],
            items: items
        )
        #expect(ids == ["b", "a"])
    }

    @Test func anyVideoHidesSlideshow() {
        let mixed: [ShowGridItem] = [
            .media(makeItem(id: "still")),
            .media(makeItem(id: "clip", isVideo: true))
        ]
        #expect(
            ShowSelectSlideshow.imageIds(
                selectedIds: ["still", "clip"],
                items: mixed
            ) == nil
        )
    }

    @Test func videosOnlyAreNotASlideshow() {
        let items: [ShowGridItem] = [
            .media(makeItem(id: "clip", isVideo: true))
        ]
        let ids = ShowSelectSlideshow.imageIds(
            selectedIds: ["clip"],
            items: items
        )
        #expect(ids == nil)
    }

    @Test func toolInSelectionBlocks() {
        let items: [ShowGridItem] = [
            .camera,
            .media(makeItem(id: "still"))
        ]
        let ids = ShowSelectSlideshow.imageIds(
            selectedIds: [ShowToolToken.camera, "still"],
            items: items
        )
        #expect(ids == nil)
    }

    @Test func websiteInSelectionBlocks() {
        let page = WebPage(
            title: "Site",
            url: URL(string: "https://example.com")!
        )
        let items: [ShowGridItem] = [
            .website(page),
            .media(makeItem(id: "still"))
        ]
        let ids = ShowSelectSlideshow.imageIds(
            selectedIds: [page.id.uuidString, "still"],
            items: items
        )
        #expect(ids == nil)
    }

    @Test func emptySelectionIsNil() {
        let ids = ShowSelectSlideshow.imageIds(
            selectedIds: [],
            items: [.media(makeItem(id: "still"))]
        )
        #expect(ids == nil)
    }

    private func makeItem(id: String, isVideo: Bool = false) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: id,
            isVideo: isVideo,
            duration: isVideo ? 12 : 0,
            isAvailable: true
        )
    }
}
