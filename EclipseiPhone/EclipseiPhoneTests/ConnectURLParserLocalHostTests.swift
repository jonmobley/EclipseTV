//
//  ConnectURLParserLocalHostTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  The Mac remote only connects to Eclipse on the same Wi-Fi. A scanned code,
//  tapped link or typed address that names an outside server is refused, so
//  the PIN typed afterwards can never leave the local network
//  (AUDIT_2026-11-02 P-1).
//

import Testing
import Foundation
@testable import EclipseiPhone

struct ConnectURLParserLocalHostTests {

    @Test func acceptsLocalNetworkAddresses() {
        let accepted = [
            "eclipse://mac-remote?h=192.168.1.10&p=7878#t=abc",
            "http://10.0.0.5:7878/#t=abc",
            "eclipse-mac.local",
            "172.16.4.2:7878",
            "127.0.0.1",
            "Studio-Mac",
        ]
        for raw in accepted {
            #expect(ConnectURLParser.parse(raw) != nil, "\(raw) should be accepted")
        }
    }

    @Test func refusesOutsideServers() {
        let refused = [
            "eclipse://mac-remote?h=evil.example.com&p=443#t=abc",
            "https://evil.example.com/#t=abc",
            "8.8.8.8:7878",
            "remote.example.org",
        ]
        for raw in refused {
            #expect(ConnectURLParser.parse(raw) == nil, "\(raw) should be refused")
        }
    }

    @Test func keepsTokenAndPortForLocalLinks() throws {
        let info = try #require(
            ConnectURLParser.parse("eclipse://mac-remote?h=192.168.1.10&p=7900#t=tok123")
        )
        #expect(info.baseURL.host == "192.168.1.10")
        #expect(info.baseURL.port == 7900)
        #expect(info.bootstrapToken == "tok123")
    }
}
