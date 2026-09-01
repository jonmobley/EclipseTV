//
//  LiveHeaderViewLiveBadgeTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewLiveBadgeTests {

    @Test func overlayHidesLiveBadgeInPracticePreview() {
        let header = makeHeader()
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            showsLiveBadge: false
        )
        #expect(header.liveBadge.isHidden)
    }

    @Test func overlayShowsLiveBadgeWhenExternalDisplayIsConnected() {
        let header = makeHeader()
        header.configureOverlay(
            title: "Camera",
            systemImage: "camera.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            showsLiveBadge: true
        )
        #expect(header.liveBadge.isHidden == false)
    }

    @Test func mediaHidesLiveBadgeInPracticePreview() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: false,
            showsLiveBadge: false
        )
        #expect(header.liveBadge.isHidden)
    }

    @Test func mediaShowsLiveBadgeWhenExternalDisplayIsConnected() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: false,
            showsLiveBadge: true
        )
        #expect(header.liveBadge.isHidden == false)
    }

    @Test func lockModeChangesLiveBadgeTextToLiveLocked() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        #expect(header.liveBadge.text == "LIVE")

        header.setOutputLocked(true)
        #expect(header.liveBadge.text == "LIVE LOCKED")
        #expect(header.liveBadge.backgroundColor == UIColor.systemOrange)

        header.setOutputLocked(false)
        #expect(header.liveBadge.text == "LIVE")
        #expect(header.liveBadge.backgroundColor == UIColor.systemRed)
    }

    private func makeHeader() -> LiveHeaderView {
        LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
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
}
