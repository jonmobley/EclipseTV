//
//  WebSheetSingleInstanceTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Pins the "one website sheet at a time" detection. Openers use this to navigate the
//  open browser (normal Back history) instead of stacking a second sheet that fought
//  over the warm WKWebView and left AirPlay on the previous site.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct WebSheetSingleInstanceTests {

    private static let samplePage = WebPage(
        title: "Example",
        url: URL(string: "https://example.com")!
    )

    @Test func listAllowsTheFirstBrowser() {
        let list = WebPagesViewController()
        _ = UINavigationController(rootViewController: list)
        #expect(!list.isAlreadyOpen(WebRemoteViewController.self))
        #expect(list.openController(ofType: WebRemoteViewController.self) == nil)
    }

    @Test func listFindsTheOpenBrowserForNavigate() {
        let list = WebPagesViewController()
        let nav = UINavigationController(rootViewController: list)
        let browser = WebRemoteViewController(page: Self.samplePage)
        nav.setViewControllers(nav.viewControllers + [browser], animated: false)
        #expect(list.isAlreadyOpen(WebRemoteViewController.self))
        #expect(list.openController(ofType: WebRemoteViewController.self) === browser)
    }

    /// The browser itself must not be mistaken for an unrelated screen being open.
    @Test func openBrowserDoesNotBlockOtherScreens() {
        let browser = WebRemoteViewController(page: Self.samplePage)
        _ = UINavigationController(rootViewController: browser)
        #expect(!browser.isAlreadyOpen(WebPagesViewController.self))
    }
}
