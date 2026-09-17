//
//  HomeMusicLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct HomeMusicLayoutTests {

    @Test func compactWidthAlwaysPagesRegardlessOfPin() {
        #expect(HomeMusicLayout.mode(horizontalSizeClass: .compact, pinned: false) == .paging)
        #expect(HomeMusicLayout.mode(horizontalSizeClass: .compact, pinned: true) == .paging)
    }

    @Test func regularWidthAlwaysUsesDrawer() {
        #expect(HomeMusicLayout.mode(horizontalSizeClass: .regular, pinned: false) == .drawer)
        #expect(HomeMusicLayout.mode(horizontalSizeClass: .regular, pinned: true) == .drawer)
    }

    @Test func sidebarKeepsPreferredWidthWhenLibraryFits() {
        #expect(HomeMusicLayout.sidebarWidth(for: 1024) == 340)
        #expect(HomeMusicLayout.sidebarWidth(for: 1366) == 340)
    }

    @Test func sidebarShrinksBeforeLibraryDropsBelowMinimum() {
        let width = HomeMusicLayout.sidebarWidth(for: 600)
        #expect(width == 280)
    }

    @Test func settleOpenUsesProgressWhenVelocityIsCalm() {
        #expect(HomeMusicLayout.shouldSettleOpen(progress: 0.6, velocityX: 0))
        #expect(!HomeMusicLayout.shouldSettleOpen(progress: 0.4, velocityX: 0))
    }

    @Test func settleOpenRespectsFlickVelocity() {
        #expect(HomeMusicLayout.shouldSettleOpen(progress: 0.2, velocityX: -500))
        #expect(!HomeMusicLayout.shouldSettleOpen(progress: 0.8, velocityX: 500))
    }

    @Test func pinDefaultsToFalseAndRoundTrips() {
        let suite = "HomeMusicLayoutTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        #expect(!HomeMusicLayout.isPinned(defaults: defaults))
        HomeMusicLayout.setPinned(true, defaults: defaults)
        #expect(HomeMusicLayout.isPinned(defaults: defaults))
        HomeMusicLayout.setPinned(false, defaults: defaults)
        #expect(!HomeMusicLayout.isPinned(defaults: defaults))
    }
}

@MainActor
struct HomeMusicDrawerViewTests {

    @Test func openDrawerHitsThePanel() {
        let drawer = HomeMusicDrawerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        drawer.isDrawerEnabled = true
        drawer.panelWidth = 340
        drawer.layoutIfNeeded()
        drawer.setOpen(true, animated: false)
        #expect(drawer.hitTest(CGPoint(x: 780, y: 300), with: nil) != nil)
        drawer.setOpen(false, animated: false)
        #expect(drawer.hitTest(CGPoint(x: 780, y: 300), with: nil) == nil)
    }

    @Test func closedDrawerDoesNotStealHits() {
        let drawer = HomeMusicDrawerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        drawer.isDrawerEnabled = true
        drawer.panelWidth = 340
        drawer.layoutIfNeeded()
        drawer.setOpen(false, animated: false)

        #expect(drawer.hitTest(CGPoint(x: 800 - 8, y: 300), with: nil) == nil)
        #expect(drawer.hitTest(CGPoint(x: 40, y: 40), with: nil) == nil)
    }

    @Test func openDrawerReportsSettledProgress() {
        let drawer = HomeMusicDrawerView(frame: CGRect(x: 0, y: 0, width: 800, height: 600))
        drawer.isDrawerEnabled = true
        drawer.setOpen(true, animated: false)
        #expect(abs(drawer.progress - 1) < 0.01)
        drawer.setOpen(false, animated: false)
        #expect(abs(drawer.progress) < 0.01)
    }
}

@MainActor
struct AudioMiniChromeZOrderTests {

    @Test func raisePutsPlayerAndBubbleAboveDrawer() {
        let host = UIView()
        let drawer = UIView()
        let player = UIView()
        let bubble = UIView()
        host.addSubview(player)
        host.addSubview(bubble)
        host.addSubview(drawer)
        #expect(
            !AudioMiniChromeZOrder.isAboveDrawer(
                player: player, bubble: bubble, drawer: drawer, in: host
            )
        )
        AudioMiniChromeZOrder.raise(player: player, bubble: bubble, in: host)
        #expect(
            AudioMiniChromeZOrder.isAboveDrawer(
                player: player, bubble: bubble, drawer: drawer, in: host
            )
        )
        let views = host.subviews
        #expect(views.firstIndex(of: bubble)! > views.firstIndex(of: player)!)
    }
}

@MainActor
struct HomeOverlayZOrderTests {

    @Test func openDrawerSitsAboveHeaderButtons() {
        let host = UIView()
        let header = UIView()
        let drawer = UIView()
        let player = UIView()
        let bubble = UIView()
        host.addSubview(header)
        host.addSubview(player)
        host.addSubview(bubble)
        host.addSubview(drawer)
        HomeOverlayZOrder.raise(
            header: header,
            player: player,
            bubble: bubble,
            drawer: drawer,
            drawerOpen: true,
            in: host
        )
        #expect(
            HomeOverlayZOrder.isDrawerAboveHeader(
                drawer: drawer, header: header, in: host
            )
        )
        let views = host.subviews
        #expect(views.last === drawer)
    }

    @Test func closedDrawerLeavesMusicBubbleOnTop() {
        let host = UIView()
        let header = UIView()
        let drawer = UIView()
        let player = UIView()
        let bubble = UIView()
        host.addSubview(header)
        host.addSubview(drawer)
        host.addSubview(player)
        host.addSubview(bubble)
        HomeOverlayZOrder.raise(
            header: header,
            player: player,
            bubble: bubble,
            drawer: drawer,
            drawerOpen: false,
            in: host
        )
        #expect(
            HomeOverlayZOrder.isDrawerAboveHeader(
                drawer: drawer, header: header, in: host
            )
        )
        let views = host.subviews
        #expect(views.last === bubble)
        #expect(views.firstIndex(of: bubble)! > views.firstIndex(of: drawer)!)
    }
}
