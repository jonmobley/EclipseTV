//
//  ThumbnailTypeIconTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ThumbnailTypeIconTests {

    @Test func symbolsMatchContentTypes() {
        #expect(ThumbnailTypeIcon.photo.systemName == "photo.fill")
        #expect(ThumbnailTypeIcon.video.systemName == "video.fill")
        #expect(ThumbnailTypeIcon.slideshow.systemName == "rectangle.stack.fill")
        #expect(ThumbnailTypeIcon.website.systemName == "safari")
        #expect(ThumbnailTypeIcon.pdf.systemName == "doc.richtext")
        #expect(ThumbnailTypeIcon.media(isVideo: false) == .photo)
        #expect(ThumbnailTypeIcon.media(isVideo: true) == .video)
    }

    @Test func photoThumbnailShowsPhotoIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.appliedIcon == .photo)
        #expect(cell.typeIconOverlay.isHidden == false)
    }

    @Test func videoThumbnailShowsVideoIconNotCenteredPlay() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.appliedIcon == .video)
        #expect(cell.typeIconOverlay.isHidden == false)
    }

    @Test func missingThumbnailHidesTypeIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: nil, isLive: false)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func websiteSpecialShowsTypeIconOnArt() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Example",
            systemImage: "safari",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .website
        )
        #expect(cell.typeIconOverlay.appliedIcon == .website)
        #expect(cell.typeIconOverlay.isHidden == false)
    }

    @Test func toolTilesDoNotGetTypeIcons() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Screensaver",
            systemImage: "sparkles.tv",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false
        )
        #expect(cell.typeIconOverlay.isHidden)
        cell.configureActionTile(title: "New Show")
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func rewindHidesVideoTypeIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.isHidden == false)
        cell.setRewindHandler { }
        #expect(cell.typeIconOverlay.isHidden)
        cell.clearRewind()
        #expect(cell.typeIconOverlay.appliedIcon == .video)
        #expect(cell.typeIconOverlay.isHidden == false)
    }

    private func makeCell() -> LibraryThumbnailCell {
        LibraryThumbnailCell(frame: CGRect(x: 0, y: 0, width: 160, height: 90))
    }

    private func makeItem(isVideo: Bool) -> LibraryItemDTO {
        LibraryItemDTO(
            id: "item",
            name: "Item",
            isVideo: isVideo,
            duration: isVideo ? 12 : 0,
            isAvailable: true
        )
    }

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
