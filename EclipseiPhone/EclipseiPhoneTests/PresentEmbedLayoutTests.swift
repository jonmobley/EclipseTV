//
//  PresentEmbedLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

struct PresentEmbedLayoutTests {

    @Test func presentURLUsesHostSizedViewport() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        let web = UIView(frame: .zero)
        host.addSubview(web)
        let present = QuestPollConfig.presentURL(code: "ABCD")
        PresentationViewController.applyWebLayout(
            to: web,
            in: host,
            pageURL: present,
            rotationDegrees: 0
        )
        #expect(web.transform == .identity)
        #expect(abs(web.bounds.width - 800) < 0.5)
        #expect(abs(web.bounds.height - 450) < 0.5)
    }

    @Test func presentURLWithVerticalAspectUsesHostSizedViewport() throws {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 450, height: 800))
        let web = UIView(frame: .zero)
        host.addSubview(web)
        let present = try #require(
            URL(string: "https://quest.eclipseapp.com/present?code=ABCD&aspect=9x16")
        )
        PresentationViewController.applyWebLayout(
            to: web,
            in: host,
            pageURL: present,
            rotationDegrees: 0
        )
        #expect(web.transform == .identity)
        #expect(abs(web.bounds.width - 450) < 0.5)
        #expect(abs(web.bounds.height - 800) < 0.5)
    }

    @Test func bookmarkURLUsesDesktopLogicalScale() {
        let host = UIView(frame: CGRect(x: 0, y: 0, width: 800, height: 450))
        let web = UIView(frame: .zero)
        host.addSubview(web)
        let bookmark = URL(string: "https://example.com/page")!
        PresentationViewController.applyWebLayout(
            to: web,
            in: host,
            pageURL: bookmark,
            rotationDegrees: 0
        )
        let logical = ExternalOutputSettings.webLogicalSize
        let expectedScale = 800 / logical.width
        #expect(abs(web.bounds.width - logical.width) < 1)
        #expect(abs(web.transform.a - expectedScale) < 0.01)
    }
}
