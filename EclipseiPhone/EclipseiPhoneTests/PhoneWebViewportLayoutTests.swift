//
//  PhoneWebViewportLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Landscape browser hides the URL nav bar so the 16:9 preview can use the
//  full stage height, centred together with its trailing button column. Vertical still leaves room for the URL bar above the stage.
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


    @Test func landscapeCardAndColumnAreCentredTogether() {
        let stage = CGRect(x: 0, y: 0, width: 852, height: 393)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 21, right: 59)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect
        )
        let column = PhoneWebViewportLayout.overlayFrames(
            panel: panel, in: stage, safeInsets: safe, count: 1
        )[0]
        let leftGap = panel.minX - max(safe.left, PhoneWebViewportLayout.sideInset)
        let groupMaxX = panel.maxX + PhoneWebViewportLayout.landscapeChromeColumn
        let rightGap = stage.maxX - max(safe.right, PhoneWebViewportLayout.sideInset) - groupMaxX
        #expect(abs(leftGap - rightGap) < 0.5)
        #expect(leftGap >= -0.5)
        // The column sits right beside the card, inside the group.
        #expect(column.minX >= panel.maxX - 0.5)
        #expect(column.maxX <= groupMaxX + 0.5)
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

    @Test func iPadUsesATopBarAndPhonesTheColumn() {
        #expect(
            PhoneWebViewportLayout.chromePlacement(
                for: CGSize(width: 820, height: 1180), isVertical: false, idiom: .pad
            ) == .topRow
        )
        #expect(
            PhoneWebViewportLayout.chromePlacement(
                for: CGSize(width: 1180, height: 820), isVertical: false, idiom: .pad
            ) == .topRow
        )
        #expect(
            PhoneWebViewportLayout.chromePlacement(
                for: CGSize(width: 852, height: 393), isVertical: false, idiom: .phone
            ) == .trailingColumn
        )
        #expect(
            PhoneWebViewportLayout.chromePlacement(
                for: CGSize(width: 820, height: 1180), isVertical: true, idiom: .pad
            ) == .trailingColumn
        )
    }

    @Test func topBarPutsButtonsInTheCornerAndChipsOnTheLeft() {
        let stage = CGRect(x: 0, y: 0, width: 1180, height: 820)
        let safe = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage,
            isVertical: false,
            safeInsets: safe,
            aspect: landscapeAspect,
            placement: .topRow
        )
        let barTop = max(safe.top, PhoneWebViewportLayout.sideInset)
        #expect(abs(panel.minY - (barTop + PhoneWebViewportLayout.topBarHeight)) < 0.5)
        #expect(abs(panel.midX - stage.midX) < 0.5)
        #expect(abs(panel.width / panel.height - landscapeAspect) < 0.01)

        let frames = PhoneWebViewportLayout.overlayFrames(
            panel: panel, in: stage, safeInsets: safe, placement: .topRow, count: 4
        )
        #expect(frames.count == 4)
        // First button (Close) in the corner; the rest march left.
        #expect(abs(frames[0].maxX - (stage.maxX - PhoneWebViewportLayout.sideInset)) < 0.5)
        #expect(frames[1].maxX < frames[0].minX)
        for frame in frames {
            #expect(abs(frame.minY - barTop) < 0.5)
            #expect(frame.maxY <= panel.minY + 0.5)
        }

        let strip = PhoneWebViewportLayout.tabStripFrame(
            panel: panel, in: stage, safeInsets: safe, placement: .topRow, buttonCount: 4
        )
        #expect(abs(strip.minX - panel.minX) < 0.5)
        #expect(strip.maxX < frames[3].minX)
        #expect(strip.minY >= barTop)
        #expect(strip.maxY <= panel.minY + 0.5)
    }

    @Test func topBarCardIsNotTallerThanAnUprightiPad() {
        let stage = CGRect(x: 0, y: 0, width: 820, height: 1180)
        let safe = UIEdgeInsets(top: 24, left: 0, bottom: 20, right: 0)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage, isVertical: false, safeInsets: safe,
            aspect: landscapeAspect, placement: .topRow
        )
        #expect(abs(panel.width - (stage.width - 2 * PhoneWebViewportLayout.sideInset)) < 0.5)
        #expect(panel.maxY < stage.midY)
    }

    @Test func tabStripSitsAboveTheCard() {
        let stage = CGRect(x: 0, y: 0, width: 844, height: 390)
        let safe = UIEdgeInsets(top: 0, left: 59, bottom: 0, right: 21)
        let withStrip = PhoneWebViewportLayout.panelRect(
            in: stage, isVertical: false, safeInsets: safe,
            aspect: landscapeAspect, showsTabStrip: true
        )
        let without = PhoneWebViewportLayout.panelRect(
            in: stage, isVertical: false, safeInsets: safe, aspect: landscapeAspect
        )
        #expect(withStrip.height < without.height)
        let strip = PhoneWebViewportLayout.tabStripFrame(above: withStrip)
        #expect(strip.maxY <= withStrip.minY)
        #expect(strip.minY >= 0)
        #expect(abs(strip.width - withStrip.width) < 0.5)
        let column = PhoneWebViewportLayout.overlayFrames(
            panel: withStrip, in: stage, safeInsets: safe, showsTabStrip: true, count: 4
        )
        #expect(abs(column[0].minY - strip.minY) < 0.5)
    }

    @Test func columnHoldsSixButtonsOnTheShortestPhone() {
        // iPhone SE landscape: 667 × 375.
        let stage = CGRect(x: 0, y: 0, width: 667, height: 375)
        let panel = PhoneWebViewportLayout.panelRect(
            in: stage, isVertical: false, safeInsets: .zero, aspect: landscapeAspect
        )
        let frames = PhoneWebViewportLayout.overlayFrames(
            panel: panel, in: stage, safeInsets: .zero, count: 6
        )
        #expect(frames.last!.maxY <= stage.maxY)
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
            // Back waits for in-session history; Refresh and ⋯ are always there.
            // New Tab lives in ⋯; Auto Scroll shows only while it runs.
            #expect(browser.overlayBackButton.isHidden)
            #expect(browser.overlayRefreshButton.isHidden == false)
            #expect(browser.overlayNewTabButton.isHidden)
            #expect(browser.overlayAutoScrollButton.isHidden)
            #expect(browser.overlayBookmarksButton.isHidden == false)
            #expect(browser.overlaySendToTVButton.isHidden)
        }
    }

    @Test func verticalBarShowsRefreshAndNewTab() {
        ExternalOutputOrientationFixture.with(.portrait) {
            let browser = WebRemoteViewController(page: Self.samplePage)
            browser.loadViewIfNeeded()
            let items = browser.navigationItem.rightBarButtonItems ?? []
            #expect(items.contains { $0 === browser.refreshBarButton })
            #expect(items.contains { $0 === browser.newTabBarButton })
            #expect(!items.contains { $0 === browser.sendToTVBarButton })
        }
    }

    @Test func singleTabHidesTheStrip() {
        ExternalOutputOrientationFixture.with(.landscape) {
            let browser = WebRemoteViewController(page: Self.samplePage)
            browser.loadViewIfNeeded()
            #expect(browser.tabStripView.isHidden)
        }
    }

    @Test func showWebsitesBecomeTabs() {
        let other = WebPage(title: "Other", url: URL(string: "https://other.example")!)
        ExternalOutputOrientationFixture.with(.landscape) {
            let browser = WebRemoteViewController(
                page: other, showPages: [Self.samplePage, other]
            )
            browser.loadViewIfNeeded()
            #expect(browser.tabs.tabs.count == 2)
            #expect(browser.tabs.active.page?.id == other.id)
            #expect(browser.tabStripView.isHidden == false)
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
