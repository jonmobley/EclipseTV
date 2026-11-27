//
//  MacRemotePageTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

/// The Mac remote inside the app is the Mac's own page: where it loads from and
/// where it may go.
struct MacRemotePageTests {

    private let base = URL(string: "http://192.168.1.10:7878")!

    @Test func qrLinkCarriesItsSecretInTheFragment() throws {
        let info = try #require(
            ConnectURLParser.parse("eclipse://mac-remote?h=192.168.1.10&p=7878#t=abc-DEF_123")
        )
        let url = try #require(MacRemotePage.url(for: info))
        #expect(url.absoluteString == "http://192.168.1.10:7878/#t=abc-DEF_123")
        #expect(url.query == nil)
    }

    @Test func typedAddressOpensThePageWithNoSecret() throws {
        let info = try #require(ConnectURLParser.parse("eclipse.local"))
        let url = try #require(MacRemotePage.url(for: info))
        #expect(url.absoluteString == "http://eclipse.local:7878/")
        #expect(url.fragment == nil)
    }

    @Test func staysOnTheMacItOpened() {
        #expect(MacRemotePage.allowsNavigation(
            to: URL(string: "http://192.168.1.10:7878/"), base: base
        ))
        #expect(MacRemotePage.allowsNavigation(
            to: URL(string: "http://192.168.1.10:7878/#t=x"), base: base
        ))
        #expect(MacRemotePage.allowsNavigation(to: URL(string: "about:blank"), base: base))
    }

    @Test func refusesAnywhereElse() {
        let elsewhere = [
            "https://example.com/",
            "http://192.168.1.11:7878/",
            "http://192.168.1.10:8080/",
            "https://192.168.1.10:7878/",
            "tel:5551234",
            "eclipse://mac-remote?h=10.0.0.9"
        ]
        for raw in elsewhere {
            #expect(
                !MacRemotePage.allowsNavigation(to: URL(string: raw), base: base),
                "\(raw) should be refused"
            )
        }
        #expect(!MacRemotePage.allowsNavigation(to: nil, base: base))
    }

    @Test func backArrowScriptTalksToTheApp() {
        let script = MacRemotePage.backArrowScript
        #expect(script.contains("messageHandlers.eclipseApp"))
        for message in ["header-ready", "header-missing", "close", "pin-shown", "pin-hidden"] {
            #expect(script.contains("\"\(message)\""))
        }
    }
}
