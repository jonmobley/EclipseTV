//
//  ScrollSafeMenuButtonTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct ScrollSafeMenuButtonTests {

    /// Scroll view whose glide state the test controls.
    private final class FakeScrollView: UIScrollView {
        var gliding = false
        override var isDecelerating: Bool { gliding }
    }

    private func makeButton() -> ScrollSafeMenuButton {
        let button = ScrollSafeMenuButton(type: .system)
        button.frame = CGRect(x: 0, y: 0, width: 44, height: 44)
        button.menu = UIMenu(children: [UIAction(title: "Rename") { _ in }])
        return button
    }

    @Test func touchDownAndLongPressDoNotOpenTheMenu() throws {
        let button = makeButton()
        let interaction = try #require(button.contextMenuInteraction)
        #expect(button.contextMenuInteraction(interaction, configurationForMenuAtLocation: .zero) == nil)
    }

    @Test func touchesLandOnAPlainViewSoGridsCanScroll() throws {
        let button = makeButton()
        let hit = try #require(button.hitTest(CGPoint(x: 22, y: 22), with: nil))
        #expect(!(hit is UIControl))
        #expect(hit.isDescendant(of: button))
    }

    @Test func hiddenButtonTakesNoTouches() {
        let button = makeButton()
        button.isHidden = true
        #expect(button.hitTest(CGPoint(x: 22, y: 22), with: nil) == nil)
    }

    @Test func tapIsIgnoredWhileTheGridGlides() throws {
        let scrollView = FakeScrollView(frame: CGRect(x: 0, y: 0, width: 300, height: 300))
        let cell = UIView(frame: scrollView.bounds)
        let button = makeButton()
        cell.addSubview(button)
        scrollView.addSubview(cell)

        let hit = try #require(button.hitTest(CGPoint(x: 22, y: 22), with: nil))
        let tap = try #require(hit.gestureRecognizers?.first)
        let delegate = try #require(tap.delegate)

        #expect(delegate.gestureRecognizer?(tap, shouldReceive: UITouch()) == true)
        scrollView.gliding = true
        #expect(delegate.gestureRecognizer?(tap, shouldReceive: UITouch()) == false)
    }
}
