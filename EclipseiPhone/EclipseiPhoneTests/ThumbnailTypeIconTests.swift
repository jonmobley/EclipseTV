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
        #expect(ThumbnailTypeIcon.video.systemName == "play.fill")
        #expect(ThumbnailTypeIcon.slideshow.systemName == "rectangle.stack.fill")
        #expect(ThumbnailTypeIcon.website.systemName == "safari")
        #expect(ThumbnailTypeIcon.pdf.systemName == "doc.richtext")
        #expect(ThumbnailTypeIcon.camera.systemName == "camera.fill")
        #expect(ThumbnailTypeIcon.livePoll.systemName == "chart.bar.fill")
        #expect(ThumbnailTypeIcon.media(isVideo: false) == .photo)
        #expect(ThumbnailTypeIcon.media(isVideo: true) == .video)
        #expect(ThumbnailTypeIcon.camera.showsWithoutThumbnail)
        #expect(ThumbnailTypeIcon.livePoll.showsWithoutThumbnail)
        #expect(ThumbnailTypeIcon.photo.showsWithoutThumbnail == false)
        #expect(ThumbnailTypeIcon.video.usesPlayFill)
    }

    @Test func photoThumbnailShowsPhotoIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.appliedIcon == .photo)
        #expect(cell.typeIconOverlay.isHidden == false)
    }

    @Test func videoThumbnailShowsCornerPlayIcon() {
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

    @Test func titledCaptionStaysAtBottomWhenTypeIconIsTop() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Example",
            systemImage: "safari",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .website
        )
        cell.layoutIfNeeded()
        #expect(cell.captionLabel.textAlignment == .center)
        #expect(abs(cell.typeIconOverlay.frame.minY - ThumbnailTypeIconView.inset) < 0.5)
        #expect(cell.captionLabel.frame.minY > cell.typeIconOverlay.frame.maxY)
        let trailingInset = cell.cardView.bounds.width - cell.captionLabel.frame.maxX
        #expect(abs(trailingInset - 8) < 0.5)
    }

    @Test func captionStopsBeforeDurationPill() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        cell.captionLabel.text = "Opening hymn of the morning service"
        cell.captionLabel.isHidden = false
        cell.updateCaptionScrim()
        cell.layoutIfNeeded()
        #expect(cell.captionLabel.textAlignment == .center)
        #expect(
            cell.captionLabel.frame.maxX
                <= cell.durationLabel.frame.minX - ThumbnailTypeIconView.titleSpacing + 0.5
        )
    }

    @Test func toolTilesShowTypeIcons() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Screensaver",
            systemImage: "play.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .video
        )
        #expect(cell.typeIconOverlay.appliedIcon == .video)
        #expect(cell.typeIconOverlay.isHidden == false)

        cell.configureSpecial(
            title: "Screensaver",
            systemImage: "play.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .photo
        )
        #expect(cell.typeIconOverlay.appliedIcon == .photo)

        cell.configureSpecial(
            title: "Background",
            systemImage: "photo.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .photo
        )
        #expect(cell.typeIconOverlay.appliedIcon == .photo)
        #expect(cell.typeIconOverlay.isHidden == false)

        cell.configureCamera(isLive: false, lastFrame: nil, warmPreview: false)
        #expect(cell.typeIconOverlay.appliedIcon == .camera)
        #expect(cell.typeIconOverlay.isHidden == false)
        #expect(cell.captionLabel.textAlignment == .center)

        cell.configureActionTile(title: "New Show")
        #expect(cell.typeIconOverlay.isHidden)
        #expect(cell.captionLabel.textAlignment == .center)
    }

    @Test func videoThumbnailShowsDurationOverlay() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        cell.layoutIfNeeded()
        #expect(cell.durationOverlayText == "0:12")
        #expect(ThumbnailTypeIcon.video.systemName == "play.fill")
        // Play glyph stays in the top-leading corner, not centered on the still.
        #expect(cell.typeIconOverlay.frame.minX == 8)
        #expect(abs(cell.typeIconOverlay.frame.minY - 8) < 0.5)
    }

    @Test func photoThumbnailHidesDurationOverlay() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        #expect(cell.durationOverlayText == nil)
    }

    @Test func videoWithoutDurationHidesOverlay() {
        let cell = makeCell()
        let item = LibraryItemDTO(
            id: "item",
            name: "Item",
            isVideo: true,
            duration: 0,
            isAvailable: true
        )
        cell.configure(with: item, thumbnail: swatch(), isLive: false)
        #expect(cell.durationOverlayText == nil)
    }

    @Test func rewindKeepsVideoTypeIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.isHidden == false)
        cell.setRewindHandler { }
        #expect(cell.typeIconOverlay.appliedIcon == .video)
        #expect(cell.typeIconOverlay.isHidden == false)
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
