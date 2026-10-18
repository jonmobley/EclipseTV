//
//  ShowOfflinePlannerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowOfflinePlannerTests {

    @Test func keepsGridOrderAndIncludesSlidesAndCountdownBackgrounds() {
        let tiles: [ShowOfflinePlanner.Tile] = [
            .media(id: "a.jpg"),
            .slideshow(slideIds: ["s1.jpg", "s2.mov"]),
            .other,
            .countdown(backgroundId: "bg.mov"),
            .media(id: "b.mov")
        ]
        #expect(ShowOfflinePlanner.mediaIds(in: tiles) == [
            "a.jpg", "s1.jpg", "s2.mov", "bg.mov", "b.mov"
        ])
    }

    @Test func listsSharedMediaOnce() {
        let tiles: [ShowOfflinePlanner.Tile] = [
            .media(id: "a.jpg"),
            .slideshow(slideIds: ["a.jpg", "c.jpg"]),
            .countdown(backgroundId: "c.jpg")
        ]
        #expect(ShowOfflinePlanner.mediaIds(in: tiles) == ["a.jpg", "c.jpg"])
    }

    @Test func plainCountdownsAndOtherTilesNeedNothing() {
        let tiles: [ShowOfflinePlanner.Tile] = [
            .countdown(backgroundId: nil),
            .other,
            .slideshow(slideIds: []),
            .media(id: "")
        ]
        #expect(ShowOfflinePlanner.mediaIds(in: tiles).isEmpty)
    }
}
