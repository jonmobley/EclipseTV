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

    /// No badge means Practice Mode, not program output. VoiceOver used to
    /// announce "Live" there, telling the user an audience saw the rehearsal.
    @Test func mediaAnnouncesPracticeWhenThereIsNoLiveBadge() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: false,
            showsLiveBadge: false
        )
        #expect(header.accessibilityLabel == "Practice, Photo")
    }

    @Test func mediaAnnouncesLiveWhenTheBadgeIsShowing() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        #expect(header.accessibilityLabel == "Live, Photo")
    }

    @Test func lockModeChangesLiveBadgeTextToLockedScreen() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        #expect(header.liveBadge.text == "LIVE")

        header.setOutputLocked(true)
        #expect(header.liveBadge.text == "LOCKED SCREEN")
        #expect(header.liveBadge.backgroundColor == UIColor.systemOrange)

        header.setOutputLocked(false)
        #expect(header.liveBadge.text == "LIVE")
        #expect(header.liveBadge.backgroundColor == UIColor.liveStroke)
    }

    /// Blackout's badge uses the Mac's words, as Lock's does.
    @Test func blackoutHoldBadgeReadsBlackScreen() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        header.setBlackoutHold(true, upNext: nil)
        #expect(header.liveBadge.text == "BLACK SCREEN")

        header.setBlackoutHold(false, upNext: nil)
        #expect(header.liveBadge.text == "LIVE")
    }

    /// White Blackout reads WHITE SCREEN, dark text on a white pill.
    @Test func whiteBlackoutBadgeReadsWhiteScreen() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        header.setBlackoutHold(true, upNext: nil, kind: .white)
        #expect(header.liveBadge.text == "WHITE SCREEN")
        #expect(header.liveBadge.textColor == .black)
        header.setBlackoutHold(false, upNext: nil)
        #expect(header.liveBadge.text == "LIVE")
        #expect(header.liveBadge.textColor == .white)
    }

    /// Freeze reads FREEZE FRAME and wins over Lock, which it brings along.
    @Test func freezeBadgeReadsFreezeFrame() {
        let header = makeHeader()
        header.configure(
            with: makeStillItem(),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: true
        )
        header.setOutputLocked(true)
        header.setOutputFrozen(true)
        #expect(header.liveBadge.text == "FREEZE FRAME")
        header.setOutputFrozen(false)
        #expect(header.liveBadge.text == "LOCKED SCREEN")
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
