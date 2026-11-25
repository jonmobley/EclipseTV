//
//  HeroPhonePreviewTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct HeroPhonePreviewTests {

    private func surface(
        locked: Bool = false,
        blackout: Bool = false,
        destination: Bool = true,
        hero: Bool = true,
        operator isOperator: Bool = false
    ) -> HeroPhonePreview.TapSurface {
        HeroPhonePreview.tapSurface(
            isLiveOutputLocked: locked,
            isBlackoutHolding: blackout,
            hasOutputDestination: destination,
            showsLiveHero: hero,
            isRemoteOperator: isOperator
        )
    }

    @Test func unlockedWithADestinationGoesLive() {
        #expect(surface() == .live)
    }

    @Test func lockPreviewsInTheHero() {
        #expect(surface(locked: true) == .hero)
    }

    @Test func blackoutPreviewsInTheHero() {
        #expect(surface(blackout: true) == .hero)
    }

    @Test func nothingConnectedKeepsFullscreenPreview() {
        #expect(surface(destination: false, hero: false) == .fullscreen)
        #expect(surface(locked: true, destination: false, hero: false) == .fullscreen)
    }

    @Test func noHeroToBorrowKeepsFullscreenPreview() {
        #expect(surface(locked: true, hero: false) == .fullscreen)
    }

    /// An operator's hero follows the director's program; it is never borrowed.
    @Test func operatorKeepsFullscreenPreview() {
        #expect(surface(locked: true, operator: true) == .fullscreen)
    }

    @Test func toolsAndVideoLinksAreNotPreviewedInTheHero() {
        let media = LibraryItemDTO(id: "a.jpg", name: "a", isVideo: false, duration: 0)
        let site = WebPage(title: "Site", url: URL(string: "https://a.example")!)
        let video = WebPage(title: "Clip", url: URL(string: "https://www.youtube.com/watch?v=dQw4w9WgXcQ")!)
        #expect(HeroPhonePreview.canPreview(.media(media)))
        #expect(HeroPhonePreview.canPreview(.website(site)))
        #expect(HeroPhonePreview.canPreview(.logo))
        #expect(HeroPhonePreview.canPreview(.screensaver))
        #expect(HeroPhonePreview.canPreview(.camera) == false)
        #expect(HeroPhonePreview.canPreview(.add) == false)
        #expect(video.videoLink != nil)
        #expect(HeroPhonePreview.canPreview(.website(video)) == false)
    }

    @Test func tappingThePreviewedTileOpensFullscreen() {
        #expect(
            HeroPhonePreview.tapAction(tappedId: "a", previewedId: "a", isLiveOrHeld: false)
                == .openFullscreen
        )
    }

    @Test func tappingTheLiveTileGoesBackToLive() {
        #expect(
            HeroPhonePreview.tapAction(tappedId: "live", previewedId: "a", isLiveOrHeld: true)
                == .backToLive
        )
    }

    @Test func tappingAnotherTilePreviewsIt() {
        #expect(
            HeroPhonePreview.tapAction(tappedId: "b", previewedId: "a", isLiveOrHeld: false)
                == .preview
        )
        #expect(
            HeroPhonePreview.tapAction(tappedId: "b", previewedId: nil, isLiveOrHeld: false)
                == .preview
        )
    }

    @MainActor
    @Test func heroSaysPreviewAndOffersAWayBack() {
        let header = LiveHeaderView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        header.configure(
            with: LibraryItemDTO(id: "a.jpg", name: "Photo", isVideo: false, duration: 0),
            thumbnail: nil,
            isOnline: true,
            showsLiveBadge: false
        )
        header.setOutputLocked(true)
        header.setPhonePreview(true, returnTitle: "Back to Live")
        #expect(header.liveBadge.text == "PREVIEW")
        #expect(header.liveBadge.isHidden == false)
        #expect(header.phonePreviewReturnButton?.configuration?.title == "Back to Live")
        #expect(header.accessibilityLabel?.hasPrefix("Preview on this phone only") == true)

        header.setPhonePreview(false, returnTitle: "Back to Live")
        #expect(header.liveBadge.text == "LOCKED SCREEN")
        #expect(header.phonePreviewReturnButton == nil)
    }
}
