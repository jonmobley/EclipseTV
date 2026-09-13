//
//  VideoPreviewTitleTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Pins the title floating over a playing video Preview: a third of the way down the
//  picture rather than into the letterbox above it, clear of the Close row, and only
//  while the picture is moving.
//

import AVKit
import Testing
import UIKit
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct VideoPreviewTitleTests {

    private let playerBounds = CGRect(x: 0, y: 0, width: 390, height: 844)
    private let landscapeClip = CGSize(width: 1920, height: 1080)

    @Test func sitsAThirdDownAFullBleedPicture() {
        let centerY = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: playerBounds,
            presentationSize: CGSize(width: 390, height: 844),
            playerBounds: playerBounds,
            minimumCenterY: 0
        )
        #expect(abs(centerY - 844 / 3) < 0.5)
    }

    @Test func followsTheLetterboxedPictureNotThePlayer() {
        let picture = VideoPreviewTitleLayout.pictureRect(
            presentationSize: landscapeClip, playerBounds: playerBounds
        )
        #expect(abs(picture.height - 390 * 1080 / 1920) < 0.5)
        #expect(abs(picture.midY - playerBounds.midY) < 0.5)

        let centerY = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: .zero,
            presentationSize: landscapeClip,
            playerBounds: playerBounds,
            minimumCenterY: 0
        )
        #expect(abs(centerY - (picture.minY + picture.height / 3)) < 0.5)
        #expect(centerY > picture.minY)
        #expect(centerY < picture.midY)
    }

    @Test func prefersVideoBoundsOnceThePlayerHasLaidThePictureOut() {
        let laidOut = CGRect(x: 0, y: 200, width: 390, height: 300)
        let centerY = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: laidOut,
            presentationSize: landscapeClip,
            playerBounds: playerBounds,
            minimumCenterY: 0
        )
        #expect(abs(centerY - 300) < 0.5)
    }

    @Test func fallsBackToThePlayerWhileTheSizeIsUnknown() {
        let centerY = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: .zero,
            presentationSize: .zero,
            playerBounds: playerBounds,
            minimumCenterY: 0
        )
        #expect(abs(centerY - 844 / 3) < 0.5)
    }

    @Test func staysClearOfTheCloseRow() {
        let shortPicture = CGRect(x: 0, y: 0, width: 390, height: 120)
        let minimumCenterY = 59 + VideoPreviewTitleLayout.minimumTopInset
        let centerY = VideoPreviewTitleLayout.titleCenterY(
            videoBounds: shortPicture,
            presentationSize: .zero,
            playerBounds: shortPicture,
            minimumCenterY: minimumCenterY
        )
        #expect(centerY == minimumCenterY)
    }

    @Test func showsOnlyWhileThePictureIsMoving() {
        #expect(VideoPreviewTitleLayout.isVisible(hasTitle: true, isPlaying: true))
        #expect(
            VideoPreviewTitleLayout.isVisible(hasTitle: true, isPlaying: false) == false
        )
        #expect(
            VideoPreviewTitleLayout.isVisible(hasTitle: false, isPlaying: true) == false
        )
    }

    @Test func previewInstallsTheTitleUnderTheSystemControls() {
        let preview = LocalVideoPreviewViewController(
            fileURL: URL(fileURLWithPath: "/tmp/eclipse-title-clip.mp4"),
            overlayTitle: "Opening hymn"
        )
        preview.loadViewIfNeeded()

        #expect(preview.overlayTitleLabel.text == "Opening hymn")
        #expect(preview.overlayTitleLabel.superview === preview.contentOverlayView)
        // Taps have to reach the player, and the title fades in with playback.
        #expect(preview.overlayTitleLabel.isUserInteractionEnabled == false)
        #expect(preview.overlayTitleLabel.alpha == 0)
    }

    @Test func previewWithoutATitleAddsNoLabel() {
        let preview = LocalVideoPreviewViewController(
            fileURL: URL(fileURLWithPath: "/tmp/eclipse-title-clip.mp4")
        )
        preview.loadViewIfNeeded()

        #expect(preview.overlayTitleLabel.superview == nil)
    }

    @Test func titleFallsBackToTheItemName() {
        let id = "title-preview-\(UUID().uuidString)"
        defer { MediaTitleStore.clear(forId: id) }
        let item = LibraryItemDTO(
            id: id,
            name: "IMG_2001.MOV",
            isVideo: true,
            duration: 12,
            isAvailable: true
        )

        #expect(MediaTitleStore.displayTitle(for: item) == "IMG_2001.MOV")
        MediaTitleStore.setTitle("Offering video", forId: id)
        #expect(MediaTitleStore.displayTitle(for: item) == "Offering video")
    }
}
