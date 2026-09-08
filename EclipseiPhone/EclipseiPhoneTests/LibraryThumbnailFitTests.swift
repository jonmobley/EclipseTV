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

    /// Cold launch: the tile is configured before its thumbnail is decoded, then the
    /// bitmap arrives through `applyLoadedThumbnail`. It must still be cropped.
    @Test func lateThumbnailAppliesCustomFraming() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            forId: id
        )

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: nil, isLive: false)
        #expect(cell.isShowingPlaceholder)

        cell.applyLoadedThumbnail(swatch(side: 100))
        #expect(cell.imageView.contentMode == .scaleAspectFit)
        #expect(approximately(cell.imageView.image?.size, side: 50))
    }

    @Test func lateThumbnailKeepsFillForFillStill() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(with: makeStill(id: id), thumbnail: nil, isLive: false)
        cell.applyLoadedThumbnail(swatch(side: 100))
        #expect(cell.imageView.contentMode == .scaleAspectFill)
        #expect(approximately(cell.imageView.image?.size, side: 100))
    }

    @Test func lateThumbnailLetterboxesVideo() {
        let id = uniqueId()
        defer { MediaFitSettings.clear(forId: id) }
        MediaFitSettings.setMode(.fill, forId: id)

        let cell = makeCell()
        cell.configure(with: makeVideo(id: id), thumbnail: nil, isLive: false)
        cell.applyLoadedThumbnail(swatch(side: 100))
        #expect(cell.imageView.contentMode == .scaleAspectFit)
        #expect(approximately(cell.imageView.image?.size, side: 100))
    }

    /// A reload that misses the thumbnail cache keeps the previous art. It must be
    /// re-framed from the original, not cropped a second time.
    @Test func cacheMissReconfigureDoesNotCropTwice() {
        let id = uniqueId()
        defer { MediaFramingStore.clear(forId: id) }
        MediaFramingStore.set(
            MediaFraming(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
            forId: id
        )

        let cell = makeCell()
        let still = makeStill(id: id)
        cell.configure(with: still, thumbnail: swatch(side: 100), isLive: false)
        #expect(approximately(cell.imageView.image?.size, side: 50))

        cell.configure(with: still, thumbnail: nil, isLive: false)
        #expect(!cell.isShowingPlaceholder)
        #expect(approximately(cell.imageView.image?.size, side: 50))
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

    private func approximately(_ size: CGSize?, side: CGFloat) -> Bool {
        guard let size else { return false }
        return abs(size.width - side) < 1 && abs(size.height - side) < 1
    }
}
