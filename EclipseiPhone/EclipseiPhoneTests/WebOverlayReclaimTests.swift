//
//  WebOverlayReclaimTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

struct WebOverlayReclaimTests {

    private static let pageURL = URL(string: "https://example.com")!

    @Test func aDroppedWebOverlayIsRestored() {
        #expect(
            WebOverlayReclaim.allowsRestore(lastContent: .web(Self.pageURL))
        )
    }

    @Test func aStillThatTookProgramKeepsIt() {
        #expect(
            WebOverlayReclaim.allowsRestore(
                lastContent: .image(url: Self.pageURL, fill: false, framing: nil)
            ) == false
        )
    }

    @Test func aBlackoutKeepsProgram() {
        #expect(WebOverlayReclaim.allowsRestore(lastContent: .black) == false)
    }

    @Test func nothingPresentedIsNotAWebPageToRestore() {
        // Preview-only taps never put the page on output, so a commit from the
        // browser must not be the thing that makes it live.
        #expect(WebOverlayReclaim.allowsRestore(lastContent: nil) == false)
    }
}
