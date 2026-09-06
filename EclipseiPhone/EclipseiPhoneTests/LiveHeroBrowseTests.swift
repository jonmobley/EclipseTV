//
//  LiveHeroBrowseTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
@testable import EclipseiPhone

struct LiveHeroBrowseTests {

    @Test func swipeStepsToTheNextStillInShowOrder() {
        let items = [item("a"), item("b"), item("c")]
        #expect(LiveHeroBrowse.target(from: "b", in: items, delta: 1)?.id == "c")
        #expect(LiveHeroBrowse.target(from: "b", in: items, delta: -1)?.id == "a")
    }

    @Test func endsClampInsteadOfWrapping() {
        let items = [item("a"), item("b")]
        #expect(LiveHeroBrowse.target(from: "b", in: items, delta: 1) == nil)
        #expect(LiveHeroBrowse.target(from: "a", in: items, delta: -1) == nil)
    }

    @Test func videosAndPurgedItemsAreSkipped() {
        let items = [
            item("still"),
            item("video", isVideo: true),
            item("purged", isAvailable: false),
            item("next")
        ]
        #expect(LiveHeroBrowse.target(from: "still", in: items, delta: 1)?.id == "next")
        #expect(LiveHeroBrowse.target(from: "next", in: items, delta: -1)?.id == "still")
    }

    @Test func liveVideoHasNoBrowseTarget() {
        let items = [item("a"), item("video", isVideo: true), item("c")]
        #expect(LiveHeroBrowse.target(from: "video", in: items, delta: 1) == nil)
        #expect(LiveHeroBrowse.canBrowse(from: "video", in: items) == false)
    }

    @Test func toolOrOverlayLiveIsNotBrowsable() {
        let items = [item("a"), item("b")]
        #expect(LiveHeroBrowse.canBrowse(from: nil, in: items) == false)
        #expect(LiveHeroBrowse.canBrowse(from: "camera", in: items) == false)
    }

    @Test func aLoneStillIsNotBrowsable() {
        let items = [item("a"), item("video", isVideo: true)]
        #expect(LiveHeroBrowse.canBrowse(from: "a", in: items) == false)
        #expect(LiveHeroBrowse.canBrowse(from: "a", in: [item("a"), item("b")]))
    }

    @Test func zeroDeltaIsANoOp() {
        let items = [item("a"), item("b")]
        #expect(LiveHeroBrowse.target(from: "a", in: items, delta: 0) == nil)
    }

    // MARK: - Helpers

    private func item(
        _ id: String,
        isVideo: Bool = false,
        isAvailable: Bool = true
    ) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: id,
            isVideo: isVideo,
            duration: isVideo ? 12 : 0,
            isAvailable: isAvailable
        )
    }
}
