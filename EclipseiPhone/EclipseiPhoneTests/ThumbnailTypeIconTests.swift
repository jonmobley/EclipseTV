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
        #expect(ThumbnailTypeIcon.slideshow.systemName == "photo.on.rectangle.angled")
        #expect(ThumbnailTypeIcon.website.systemName == "globe")
        #expect(ThumbnailTypeIcon.webVideo.systemName == "play.rectangle.fill")
        #expect(ThumbnailTypeIcon.pdf.systemName == "doc.text")
        #expect(ThumbnailTypeIcon.prompter.systemName == "text.viewfinder")
        // Tiles carry no corner glyph (like the Mac app).
        #expect(ThumbnailTypeIconView.showsOnTiles == false)
        #expect(ThumbnailTypeIcon.camera.systemName == "camera.fill")
        #expect(ThumbnailTypeIcon.livePoll.systemName == "chart.bar.fill")
        #expect(ThumbnailTypeIcon.countdown.systemName == "timer")
        #expect(ThumbnailTypeIcon.webVideo.spokenName == "video link")
        #expect(ThumbnailTypeIcon.webVideo.usesPlayFill == false)
        #expect(ThumbnailTypeIcon.media(isVideo: false) == .photo)
        #expect(ThumbnailTypeIcon.media(isVideo: true) == .video)
        #expect(ThumbnailTypeIcon.camera.showsWithoutThumbnail)
        #expect(ThumbnailTypeIcon.livePoll.showsWithoutThumbnail)
        #expect(ThumbnailTypeIcon.countdown.showsWithoutThumbnail)
        #expect(ThumbnailTypeIcon.photo.showsWithoutThumbnail == false)
        #expect(ThumbnailTypeIcon.camera.hidesCenterPlaceholder)
        #expect(ThumbnailTypeIcon.countdown.hidesCenterPlaceholder)
        #expect(ThumbnailTypeIcon.livePoll.hidesCenterPlaceholder == false)
        #expect(ThumbnailTypeIcon.photo.showsOnThumbnail == false)
        #expect(ThumbnailTypeIcon.video.showsOnThumbnail)
        #expect(ThumbnailTypeIcon.video.usesPlayFill)
    }

    @Test func photoThumbnailHidesTypeIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func videoThumbnailHasNoCornerIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func missingThumbnailHidesTypeIcon() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: nil, isLive: false)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func applyLoadedThumbnailFillsPlaceholder() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: nil, isLive: false)
        #expect(cell.isShowingPlaceholder)

        cell.applyLoadedThumbnail(swatch())

        #expect(cell.isShowingPlaceholder == false)
    }

    @Test func applyLoadedThumbnailRevealsSpecialTileArt() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Deck",
            systemImage: "photo.on.rectangle.angled",
            thumbnail: nil,
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .slideshow
        )
        #expect(cell.imageView.alpha == 0)

        cell.applyLoadedThumbnail(swatch())

        #expect(cell.isShowingPlaceholder == false)
        #expect(cell.imageView.alpha == 1)
        #expect(cell.placeholderIcon.isHidden)
        #expect(cell.typeIconOverlay.appliedIcon == nil)
    }

    @Test func applyLoadedThumbnailKeepsCornerIconHidden() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: nil, isLive: false)
        #expect(cell.typeIconOverlay.isHidden)

        cell.applyLoadedThumbnail(swatch())

        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func websiteSpecialHasNoCornerIconOnArt() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Example",
            systemImage: "globe",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .website
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
    }

    @Test func titledCaptionStaysAtBottomLeft() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Example",
            systemImage: "globe",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .website
        )
        cell.layoutIfNeeded()
        #expect(cell.captionLabel.textAlignment == .left)
        #expect(cell.typeIconOverlay.isHidden)
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
        #expect(cell.captionLabel.textAlignment == .left)
        #expect(
            cell.captionLabel.frame.maxX
                <= cell.durationLabel.frame.minX - ThumbnailTypeIconView.titleSpacing + 0.5
        )
    }

    @Test func toolTilesHaveNoCornerIcons() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Screensaver",
            systemImage: "play.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .video
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)

        cell.configureSpecial(
            title: "Screensaver",
            systemImage: "play.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .photo
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)

        cell.configureSpecial(
            title: "Background",
            systemImage: "photo.fill",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .photo
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)

        cell.configureCamera(isLive: false, lastFrame: nil, warmPreview: false)
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
        #expect(cell.captionLabel.textAlignment == .left)

        cell.configureSpecial(
            title: "QuestPoll",
            systemImage: "chart.bar.fill",
            thumbnail: nil,
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .livePoll
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
        // A poll card has no preview or clock, so it keeps the centred glyph.
        #expect(cell.placeholderIcon.isHidden == false)

        cell.configureSpecial(
            title: "Countdown",
            systemImage: "timer",
            thumbnail: nil,
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .countdown
        )
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
        #expect(cell.placeholderIcon.isHidden)

        cell.configureActionTile(title: "New Show")
        #expect(cell.typeIconOverlay.isHidden)
        #expect(cell.captionLabel.textAlignment == .left)
    }

    @Test func videoThumbnailShowsDurationOverlay() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        cell.layoutIfNeeded()
        #expect(cell.durationOverlayText == "0:12")
        #expect(ThumbnailTypeIcon.video.systemName == "play.fill")
        // The duration is what marks a video now that tiles have no corner glyph.
        #expect(cell.typeIconOverlay.isHidden)
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

    @Test func rewindLeavesCornerIconHidden() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.typeIconOverlay.isHidden)
        cell.setRewindHandler { }
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
        cell.clearRewind()
        #expect(cell.typeIconOverlay.appliedIcon == nil)
        #expect(cell.typeIconOverlay.isHidden)
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
