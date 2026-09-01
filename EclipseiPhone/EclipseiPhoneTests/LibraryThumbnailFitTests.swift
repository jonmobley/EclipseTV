//
//  LibraryThumbnailFitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct LibraryThumbnailFitTests {

    @Test func stillThumbnailLetterboxesWhenFit() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fit, forId: id)

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: swatch(), isLive: false)
        #expect(cell.imageView.contentMode == .scaleAspectFit)
    }

    @Test func stillThumbnailCropsWhenFill() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: swatch(), isLive: false)
        #expect(cell.imageView.contentMode == .scaleAspectFill)
    }

    @Test func videoThumbnailAlwaysLetterboxes() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(with: makeVideo(id: id), thumbnail: swatch(), isLive: false)
        #expect(cell.imageView.contentMode == .scaleAspectFit)
        #expect(cell.cardView.backgroundColor == UIColor.black)
    }

    @Test func explicitContentModeOverridesStoredFit() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(
            with: makeStill(id: id),
            thumbnail: swatch(),
            isLive: false,
            thumbnailContentMode: .scaleAspectFit
        )
        #expect(cell.imageView.contentMode == .scaleAspectFit)
    }

    @Test func thumbnailContentModeMatchesScreenFit() {
        let stillId = uniqueId()
        let videoId = uniqueId()
        defer {
            MediaFitSettings.clear(forId: stillId)
            MediaFitSettings.clear(forId: videoId)
        }
        MediaFitSettings.setMode(.fill, forId: stillId)
        #expect(
            MediaFitSettings.thumbnailContentMode(for: makeStill(id: stillId))
                == .scaleAspectFill
        )
        #expect(
            MediaFitSettings.thumbnailContentMode(for: makeStill(id: uniqueId()))
                == .scaleAspectFit
        )
        #expect(
            MediaFitSettings.thumbnailContentMode(for: makeVideo(id: videoId))
                == .scaleAspectFit
        )
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    private func makeStill(id: String) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: "Photo",
            isVideo: false,
            duration: 0,
            isAvailable: true
        )
    }

    private func makeVideo(id: String) -> LibraryItemDTO {
        LibraryItemDTO(
            id: id,
            name: "Clip",
            isVideo: true,
            duration: 12,
            isAvailable: true
        )
    }

    private func uniqueId() -> String {
        "fit-test-\(UUID().uuidString)"
    }

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
