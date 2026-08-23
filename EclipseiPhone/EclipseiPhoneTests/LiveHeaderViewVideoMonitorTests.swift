//
//  LiveHeaderViewVideoMonitorTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewVideoMonitorTests {

    @Test func remoteMonitorHidesPosterAndFilmGlyph() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.configure(
            with: makeVideoItem(),
            thumbnail: swatch(),
            isOnline: true,
            showsLocalTransport: true,
            usesRemoteVideoMonitor: true
        )

        #expect(header.backgroundColor == UIColor.black)
        #expect(header.imageView.image == nil)
        #expect(header.imageView.isHidden)
        #expect(header.placeholderIcon.isHidden)
        #expect(header.wantsPlaybackControls)
        #expect(header.controls.isHidden == false)
    }

    @Test func phoneVideoPreviewIsBlackWithoutFilmGlyph() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.configure(
            with: makeVideoItem(),
            thumbnail: nil,
            isOnline: false,
            showsLocalTransport: true
        )

        #expect(header.backgroundColor == UIColor.black)
        #expect(header.placeholderIcon.isHidden)
    }

    @Test func posterStaysVisibleForLibraryStills() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let poster = swatch()
        header.configure(
            with: makeStillItem(),
            thumbnail: poster,
            isOnline: true
        )

        #expect(header.imageView.image === poster)
        #expect(header.imageView.isHidden == false)
        #expect(header.wantsPlaybackControls == false)
    }

    private func makeVideoItem() -> LibraryItemDTO {
        LibraryItemDTO(
            id: "clip",
            name: "Clip",
            isVideo: true,
            duration: 12,
            isAvailable: true
        )
    }

    private func makeStillItem() -> LibraryItemDTO {
        LibraryItemDTO(
            id: "photo",
            name: "Photo",
            isVideo: false,
            duration: 0,
            isAvailable: true
        )
    }

    private func swatch() -> UIImage {
        UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8)).image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}
