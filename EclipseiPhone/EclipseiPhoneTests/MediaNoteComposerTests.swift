//
//  MediaNoteComposerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct MediaNoteComposerTests {

    private func compactNavigation() -> UINavigationController {
        MediaNoteComposerViewController.makeNavigation(
            itemId: "composer-test",
            traits: UITraitCollection(horizontalSizeClass: .compact),
            anchor: UIView(),
            arrows: .any
        )
    }

    @Test func phoneSheetOpensAtFullHeightOnly() throws {
        let sheet = try #require(compactNavigation().sheetPresentationController)
        #expect(sheet.detents.map(\.identifier) == [.large])
        #expect(sheet.prefersGrabberVisible)
    }

    @Test func textStopsAtTheKeyboard() throws {
        let nav = compactNavigation()
        let composer = try #require(nav.topViewController)
        composer.loadViewIfNeeded()
        let textView = try #require(composer.view.subviews.compactMap { $0 as? UITextView }.first)
        #expect(textView.keyboardDismissMode == .interactive)
        let pinned = composer.view.constraints.contains { constraint in
            constraint.firstItem === textView
                && constraint.firstAttribute == .bottom
                && constraint.secondItem === composer.view.keyboardLayoutGuide
        }
        #expect(pinned)
    }

    @Test func hideKeyboardShowsOnlyWhileEditing() throws {
        let nav = compactNavigation()
        let composer = try #require(nav.topViewController as? MediaNoteComposerViewController)
        composer.loadViewIfNeeded()
        let textView = try #require(composer.view.subviews.compactMap { $0 as? UITextView }.first)
        #expect(composer.navigationItem.leftBarButtonItem == nil)
        composer.textViewDidBeginEditing(textView)
        #expect(composer.navigationItem.leftBarButtonItem?.accessibilityLabel == "Hide Keyboard")
        composer.textViewDidEndEditing(textView)
        #expect(composer.navigationItem.leftBarButtonItem == nil)
    }
}
