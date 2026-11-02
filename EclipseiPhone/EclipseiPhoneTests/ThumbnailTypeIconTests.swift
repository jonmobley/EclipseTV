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

    @Test func contentKindsKeepSpokenNamesAndPlaceholderRules() {
        #expect(ThumbnailTypeIcon.webVideo.spokenName == "video link")
        #expect(ThumbnailTypeIcon.media(isVideo: false) == .photo)
        #expect(ThumbnailTypeIcon.media(isVideo: true) == .video)
        #expect(ThumbnailTypeIcon.camera.hidesCenterPlaceholder)
        #expect(ThumbnailTypeIcon.countdown.hidesCenterPlaceholder)
        #expect(ThumbnailTypeIcon.livePoll.hidesCenterPlaceholder == false)
    }

    /// Titles are plain text: no type glyph on the card, beside the title or in a corner.
    @Test func tilesShowNoTypeGlyph() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(typeGlyphs(in: cell).isEmpty)

        let kinds: [ThumbnailTypeIcon] = [.slideshow, .website, .webVideo, .pdf, .livePoll, .countdown]
        for kind in kinds {
            cell.configureSpecial(
                title: "Example",
                systemImage: "safari",
                thumbnail: swatch(),
                fillColor: .darkGray,
                isLive: false,
                typeIcon: kind
            )
            #expect(cell.captionLabel.text == "Example")
            #expect(typeGlyphs(in: cell).isEmpty)
        }

        cell.configureCamera(isLive: false, lastFrame: nil, warmPreview: false)
        #expect(cell.captionLabel.text == "Camera")
        #expect(typeGlyphs(in: cell).isEmpty)
    }

    @Test func specialTileStillSpeaksItsKind() {
        let cell = makeCell()
        cell.configureSpecial(
            title: "Example",
            systemImage: "safari",
            thumbnail: swatch(),
            fillColor: .darkGray,
            isLive: false,
            typeIcon: .website
        )
        #expect(cell.accessibilityLabel == "Example, website")
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
            systemImage: "rectangle.stack.fill",
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
    }

    /// Mac card layout: one-line, left-aligned title in a strip under the picture.
    @Test func titleSitsInStripUnderPicture() {
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
        #expect(cell.titleStrip.isHidden == false)
        #expect(cell.captionLabel.superview === cell.titleStrip)
        #expect(cell.captionLabel.textAlignment == .left)
        #expect(cell.captionLabel.numberOfLines == 1)
        #expect(abs(cell.titleStrip.frame.height - LibraryThumbnailCell.titleStripHeight) < 0.5)
        #expect(abs(cell.titleStrip.frame.maxY - cell.cardView.bounds.maxY) < 0.5)
        // The picture stops at the strip, so the title never covers it.
        #expect(abs(cell.imageView.frame.maxY - cell.titleStrip.frame.minY) < 0.5)
    }

    @Test func untitledPictureFillsTheCard() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        cell.layoutIfNeeded()
        #expect(cell.titleStrip.isHidden)
        #expect(abs(cell.imageView.frame.maxY - cell.cardView.bounds.maxY) < 0.5)
        // Duration pill sits on the picture.
        #expect(cell.durationLabel.frame.maxY <= cell.imageView.frame.maxY)
    }

    @Test func durationPillStaysOnThePictureAboveTheTitle() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        cell.captionLabel.text = "Opening hymn of the morning service"
        cell.captionLabel.isHidden = false
        cell.updateTitleStrip()
        cell.layoutIfNeeded()
        #expect(cell.durationLabel.frame.maxY <= cell.titleStrip.frame.minY)
    }

    @Test func slideshowRibbonShowsNoTitleStrip() {
        let cell = makeCell()
        cell.configure(
            with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false, showsTitle: false
        )
        cell.captionLabel.text = "Slide"
        cell.captionLabel.isHidden = false
        cell.updateTitleStrip()
        #expect(cell.titleStrip.isHidden)
    }

    @Test func idleCardsKeepAFaintRing() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        #expect(cell.cardView.layer.borderWidth == LibraryThumbnailCell.defaultIdleBorderWidth)
        #expect(cell.cardView.layer.cornerRadius == CornerRadii.tile)
        cell.setLive(true)
        #expect(cell.cardView.layer.borderWidth == 3)
    }

    @Test func newShowTileKeepsCenteredLabel() {
        let cell = makeCell()
        cell.configureActionTile(title: "New Show")
        #expect(cell.captionLabel.textAlignment == .center)
        cell.configure(with: makeItem(isVideo: false), thumbnail: swatch(), isLive: false)
        cell.captionLabel.text = "Slide"
        cell.captionLabel.isHidden = false
        cell.updateTitleStrip()
        #expect(cell.captionLabel.textAlignment == .left)
    }

    @Test func videoThumbnailShowsDurationOverlay() {
        let cell = makeCell()
        cell.configure(with: makeItem(isVideo: true), thumbnail: swatch(), isLive: false)
        #expect(cell.durationOverlayText == "0:12")
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

    /// Visible small image views on the card other than the centre placeholder,
    /// the ⋯ / Rewind buttons' own images and the main art.
    private func typeGlyphs(in cell: LibraryThumbnailCell) -> [UIImageView] {
        cell.cardView.subviews.compactMap { view -> UIImageView? in
            guard view !== cell.imageView, view !== cell.placeholderIcon,
                  !view.isHidden, !(view is UIButton) else { return nil }
            if let image = view as? UIImageView { return image }
            return view.subviews.lazy.compactMap { $0 as? UIImageView }.first
        }
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
