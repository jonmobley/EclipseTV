//
//  WebVideoLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct WebVideoLayoutTests {

    @Test func webVideoShellUsesNativeViewport() {
        #expect(
            PresentationViewController.webLayoutMode(
                pageURL: nil, isWebVideoShell: true
            ) == .nativeViewport
        )
    }

    @Test func questPollPresentUsesNativeViewport() {
        let present = QuestPollConfig.presentURL(code: "ABCD")
        #expect(
            PresentationViewController.webLayoutMode(pageURL: present)
                == .nativeViewport
        )
    }

    @Test func bookmarkUsesDesktopLogical() {
        let bookmark = URL(string: "https://example.com/page")!
        #expect(
            PresentationViewController.webLayoutMode(pageURL: bookmark)
                == .desktopLogical
        )
    }

    @Test func webVideoShellFillsHostWithoutDesktopScale() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        let web = UIView(frame: .zero)
        host.addSubview(web)
        PresentationViewController.applyWebLayout(
            to: web,
            in: host,
            pageURL: nil,
            rotationDegrees: 0,
            isWebVideoShell: true
        )
        #expect(web.transform == .identity)
        #expect(abs(web.bounds.width - 800) < 0.5)
        #expect(abs(web.bounds.height - 450) < 0.5)
    }
}
