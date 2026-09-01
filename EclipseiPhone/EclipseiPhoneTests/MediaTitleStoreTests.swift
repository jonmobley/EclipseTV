//
//  MediaTitleStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct MediaTitleStoreTests {

    @Test func setAndGetTitle() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }

        MediaTitleStore.setTitle("Opening hymn", forId: id)
        #expect(MediaTitleStore.title(forId: id) == "Opening hymn")
        #expect(MediaTitleStore.hasTitle(forId: id))
    }

    @Test func emptyAndWhitespaceClearsTitle() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }

        MediaTitleStore.setTitle("Keep this", forId: id)
        MediaTitleStore.setTitle("   \n\t  ", forId: id)
        #expect(MediaTitleStore.title(forId: id) == nil)
        #expect(!MediaTitleStore.hasTitle(forId: id))

        MediaTitleStore.setTitle("Again", forId: id)
        MediaTitleStore.setTitle("", forId: id)
        #expect(MediaTitleStore.title(forId: id) == nil)
    }

    @Test func titlesAreIsolatedById() {
        let a = uniqueId()
        let b = uniqueId()
        defer {
            MediaTitleStore.clear(forId: a)
            MediaTitleStore.clear(forId: b)
        }

        MediaTitleStore.setTitle("Alpha", forId: a)
        MediaTitleStore.setTitle("Beta", forId: b)
        #expect(MediaTitleStore.title(forId: a) == "Alpha")
        #expect(MediaTitleStore.title(forId: b) == "Beta")
        MediaTitleStore.clear(forId: a)
        #expect(MediaTitleStore.title(forId: a) == nil)
        #expect(MediaTitleStore.title(forId: b) == "Beta")
    }

    @Test func menuTitleSwitchesAddAndEdit() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }

        #expect(MediaTitleStore.menuTitle(forId: id) == "Add title")
        MediaTitleStore.setTitle("Welcome", forId: id)
        #expect(MediaTitleStore.menuTitle(forId: id) == "Edit title")
        MediaTitleStore.setTitle(nil, forId: id)
        #expect(MediaTitleStore.menuTitle(forId: id) == "Add title")
    }

    @Test func thumbnailShowsCenteredTitle() {
        let id = uniqueId()
        defer { MediaTitleStore.clear(forId: id) }

        let cell = LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
        let item = LibraryItemDTO(
            id: id,
            name: "IMG_1000.JPG",
            isVideo: false,
            duration: 0,
            isAvailable: true
        )
        cell.configure(with: item, thumbnail: swatch(), isLive: false)
        #expect(cell.captionLabel.isHidden)

        MediaTitleStore.setTitle("Welcome slide", forId: id)
        cell.configure(with: item, thumbnail: swatch(), isLive: false)
        cell.layoutIfNeeded()
        #expect(cell.captionLabel.isHidden == false)
        #expect(cell.captionLabel.text == "Welcome slide")
        #expect(cell.captionLabel.textAlignment == .center)
        #expect(cell.accessibilityLabel?.contains("Welcome slide") == true)
    }

    private func uniqueId() -> String {
        "title-test-\(UUID().uuidString)"
    }

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
