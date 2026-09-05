//
//  PhoneWebViewportLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Landscape browser hides the URL nav bar so the 16:9 preview can use the
//  full stage height, left-aligned, with Back / ⋯ / Close in a trailing
//  column. Vertical still leaves room for the URL bar above the stage.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct PhoneWebViewportLayoutTests {

    private let landscapeAspect: CGFloat = 16.0 / 9.0
    private let verticalAspect: CGFloat = 9.0 / 16.0

    @Test func landscapePanelUsesFullStageHeight() {
        let stage = CGRect(x: 0, y: 0, width: 844, height: 390)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 0, right: 21)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        let availableHeight = stage.height - PhoneWebViewportLayout.sideInset
        #expect(abs(panel.height - availableHeight) < 0.5)
        #expect(abs(panel.width / panel.height - landscapeAspect) < 0.01)
    }

    @Test func urlBarWouldShrinkTheLandscapePanel() {
        let full = CGRect(x: 0, y: 0, width: 844, height: 390)
        let underURLBar = CGRect(x: 0, y: 0, width: 844, height: 390 - 44)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 0, right: 21)
        let fullPanel = PhoneWebViewportLayout.panelRect(
            in: full,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        let barPanel = PhoneWebViewportLayout.panelRect(
            in: underURLBar,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        #expect(fullPanel.height > barPanel.height)
    }


    @Test func landscapePanelIsLeadingAligned() {
        let stage = CGRect(x: 0, y: 0, width: 844, height: 390)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 0, right: 21)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        let leading = max(safe.left, PhoneWebViewportLayout.sideInset)
        #expect(abs(panel.minX - leading) < 0.5)
        #expect(
            panel.maxX
                <= stage.maxX - PhoneWebViewportLayout.landscapeChromeColumn + 0.5
        )
    }

    @Test func landscapeOverlayButtonsSitOutsideThePanel() {
        let stage = CGRect(x: 0, y: 0, width: 844, height: 390)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 0, right: 21)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        let frames = PhoneWebViewportLayout.landscapeOverlayFrames(
            panel: panel,
            in: stage,
            safeInsets: safe
        )
        #expect(frames.back.minX >= panel.maxX - 0.5)
        #expect(frames.more.minX >= panel.maxX - 0.5)
        #expect(frames.close.minX >= panel.maxX - 0.5)
        #expect(frames.back.maxY <= frames.more.minY + 0.5)
        #expect(frames.more.maxY <= frames.close.minY + 0.5)
    }

    @Test func verticalPanelStaysNineBySixteen() {
        let stage = CGRect(x: 0, y: 0, width: 390, height: 720)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: true,
            safeInsets: .zero,
            aspect: verticalAspect
        )
        #expect(abs(panel.width / panel.height - verticalAspect) < 0.01)
        #expect(abs(panel.minY - 0) < 0.5)
    }
}

@MainActor
struct LandscapeBrowserChromeTests {

    private static let samplePage = WebPage(
        title: "Example",
        url: URL(string: "https://www.example.com")!
    )

    @Test func landscapeHidesURLTitle() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let browser = WebRemoteViewController(page: Self.samplePage)
            let nav = UINavigationController(rootViewController: browser)
            browser.loadViewIfNeeded()

            #expect(browser.usesOverlayBrowserChrome)
            #expect(browser.navigationItem.title == nil)
            #expect(nav.isNavigationBarHidden)
            #expect(browser.overlayBackButton.isHidden == false)
            #expect(browser.overlayBookmarksButton.isHidden == false)
        }
    }

    @Test func verticalShowsHostTitle() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let browser = WebRemoteViewController(page: Self.samplePage)
            let nav = UINavigationController(rootViewController: browser)
            browser.loadViewIfNeeded()

            #expect(browser.usesOverlayBrowserChrome == false)
            #expect(browser.navigationItem.title == "example.com")
            #expect(nav.isNavigationBarHidden == false)
            #expect(browser.overlayBackButton.isHidden)
            #expect(browser.overlayBookmarksButton.isHidden)
        }
    }
}
