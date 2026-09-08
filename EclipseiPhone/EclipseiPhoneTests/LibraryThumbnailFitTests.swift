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

    @Test func stillThumbnailLetterboxesWhenCustomFraming() {
        let id = uniqueId()
        defer {
            MediaFitSettings.clear(forId: id)
            MediaFramingStore.clear(forId: id)
        }
        MediaFitSettings.setMode(.fill, forId: id)
        MediaFramingStore.set(
            MediaFraming(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            forId: id
        )

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: swatch(), isLive: false)
        #expect(cell.imageView.contentMode == .scaleAspectFit)
    }

    @Test func lateThumbnailIsCroppedToCustomFraming() {
        // Cold launch / cache purge: the cell is built with a placeholder and the
        // disk thumb lands afterwards. It must be framed exactly like a thumb that
        // was present at configure time.
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            forId: id
        )

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: nil, isLive: false)
        #expect(cell.isShowingPlaceholder)

        cell.applyLoadedThumbnail(swatch(side: 100))
        #expect(cell.imageView.contentMode == .scaleAspectFit)
        #expect(cell.imageView.image?.size == CGSize(width: 80, height: 80))
    }

    @Test func lateThumbnailWithoutFramingKeepsScreenFit() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: nil, isLive: false)
        cell.applyLoadedThumbnail(swatch(side: 100))
        #expect(cell.imageView.contentMode == .scaleAspectFill)
        #expect(cell.imageView.image?.size == CGSize(width: 100, height: 100))
    }

    @Test func reconfigureWithoutThumbnailDoesNotCropTwice() {
        // A reload that misses the cache keeps the previous art; framing must be
        // applied to the uncropped thumb it kept, not to the already-cropped paint.
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
            forId: id
        )

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: swatch(side: 100), isLive: false)
        #expect(cell.imageView.image?.size == CGSize(width: 80, height: 80))

        cell.configure(with: makeStill(id: id), thumbnail: nil, isLive: false)
        #expect(cell.imageView.image?.size == CGSize(width: 80, height: 80))
    }

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

    private func swatch(side: CGFloat = 8) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: side, height: side)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
