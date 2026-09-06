//
//  PresentationPrewarmerTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
@testable import EclipseiPhone

@Suite(.serialized)
@MainActor
struct PresentationPrewarmerTests {

    @Test func singleSlotReplacesPreviousURL() {
        let prewarmer = PresentationPrewarmer.shared
        prewarmer.clear()
        let first = URL(fileURLWithPath: "/tmp/first.mp4")
        let second = URL(fileURLWithPath: "/tmp/second.mp4")
        prewarmer.prewarm(url: first)
        #expect(prewarmer.isPrepared(for: first))
        prewarmer.prewarm(url: second)
        #expect(prewarmer.isPrepared(for: first) == false)
        #expect(prewarmer.isPrepared(for: second))
        prewarmer.clear()
    }

    @Test func takeItemMatchesAndClearsSlot() {
        let prewarmer = PresentationPrewarmer.shared
        prewarmer.clear()
        let url = URL(fileURLWithPath: "/tmp/clip-prewarm.mp4")
        prewarmer.prewarm(url: url)
        let item = prewarmer.takeItem(matching: url)
        #expect(item != nil)
        #expect(prewarmer.isPrepared(for: url) == false)
        #expect(prewarmer.takeItem(matching: url) == nil)
        prewarmer.clear()
    }

    @Test func takeItemRejectsMismatchedURL() {
        let prewarmer = PresentationPrewarmer.shared
        prewarmer.clear()
        let prepared = URL(fileURLWithPath: "/tmp/prepared.mp4")
        let other = URL(fileURLWithPath: "/tmp/other.mp4")
        prewarmer.prewarm(url: prepared)
        #expect(prewarmer.takeItem(matching: other) == nil)
        #expect(prewarmer.isPrepared(for: prepared))
        prewarmer.clear()
    }

    @Test func clearDropsSlot() {
        let prewarmer = PresentationPrewarmer.shared
        let url = URL(fileURLWithPath: "/tmp/clear-me.mp4")
        prewarmer.prewarm(url: url)
        prewarmer.clear()
        #expect(prewarmer.isPrepared(for: url) == false)
        #expect(prewarmer.takeItem(matching: url) == nil)
    }
}
