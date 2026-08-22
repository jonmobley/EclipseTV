//
//  ShowPreviewGalleryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct ShowPreviewGalleryTests {

    @Test func swipeSetKeepsGridOrderAndSkipsNonPictures() {
        let stillA = URL(fileURLWithPath: "/tmp/a.jpg")
        let stillB = URL(fileURLWithPath: "/tmp/b.jpg")
        let saver = URL(fileURLWithPath: "/tmp/saver.mp4")
        let logo = URL(fileURLWithPath: "/tmp/logo.jpg")
        let grid: [ShowGridItem] = [
            .screensaver,
            .logo,
            .camera,
            .media(makeItem(id: "a")),
            .slideshow(Slideshow(showId: UUID(), name: "Deck")),
            .media(makeItem(id: "clip", isVideo: true)),
            .media(makeItem(id: "b")),
            .add
        ]

        let pages = ShowPreviewGallery.items(
            from: grid,
            screensaver: (saver, true),
            logoURL: logo,
            localStillURL: { id in
                switch id {
                case "a": return stillA
                case "b": return stillB
                default: return nil
                }
            }
        )

        #expect(pages.map(\.id) == [
            ShowToolToken.screensaver,
            ShowToolToken.logo,
            "a",
            "b"
        ])
        guard case .displayMode(let spec) = pages[0] else {
            Issue.record("expected Screensaver as Display Mode")
            return
        }
        #expect(spec.isVideo)
        #expect(spec.usesSeamlessLoop)
        guard case .still(let photo) = pages[2] else {
            Issue.record("expected Photo A as a still")
            return
        }
        #expect(photo.fileURL == stillA)
    }

    @Test func missingToolMediaIsOmitted() {
        let pages = ShowPreviewGallery.items(
            from: [.screensaver, .logo, .media(makeItem(id: "a"))],
            screensaver: nil,
            logoURL: nil,
            localStillURL: { _ in URL(fileURLWithPath: "/tmp/a.jpg") }
        )
        #expect(pages.map(\.id) == ["a"])
    }

    @Test func stillWithoutLocalFileIsSkipped() {
        let pages = ShowPreviewGallery.items(
            from: [.media(makeItem(id: "missing")), .media(makeItem(id: "a"))],
            screensaver: nil,
            logoURL: nil,
            localStillURL: { id in
                id == "a" ? URL(fileURLWithPath: "/tmp/a.jpg") : nil
            }
        )
        #expect(pages.map(\.id) == ["a"])
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
