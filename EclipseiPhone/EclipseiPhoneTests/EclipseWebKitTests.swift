//
//  EclipseWebKitTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import WebKit
@testable import EclipseiPhone

@MainActor
struct EclipseWebKitTests {

    @Test func configurationRequestsDesktopSite() {
        let config = EclipseWebKit.makeConfiguration()
        #expect(config.defaultWebpagePreferences.preferredContentMode == .desktop)
    }

    @Test func desktopUserAgentIsMacSafariNotIPhone() {
        let ua = EclipseWebKit.desktopUserAgent
        #expect(ua.contains("Macintosh"))
        #expect(!ua.contains("iPhone"))
        #expect(!ua.contains("Mobile"))
    }

    @Test func applyDesktopSiteSetsMacUserAgent() {
        let web = WKWebView(frame: .zero, configuration: EclipseWebKit.makeConfiguration())
        EclipseWebKit.applyDesktopSite(to: web)
        #expect(web.customUserAgent == EclipseWebKit.desktopUserAgent)
    }
}
