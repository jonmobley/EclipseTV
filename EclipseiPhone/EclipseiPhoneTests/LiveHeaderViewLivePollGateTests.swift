//
//  LiveHeaderViewLivePollGateTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct LiveHeaderViewLivePollGateTests {

    @Test func gateKeepsHeroTappableForPracticeAndStart() {
        let header = makeHeader()
        header.showLivePollGate(title: "Session 1", onPractice: {}, onStart: {})
        #expect(header.isShowingLivePollGate)
        #expect(header.isUserInteractionEnabled)
        #expect(header.placeholderIcon.isHidden)
        #expect(header.titleLabel.isHidden)
        #expect(header.liveBadge.isHidden)
    }

    @Test func hidingGateReleasesHeroInteraction() {
        let header = makeHeader()
        header.showLivePollGate(title: "Session 1", onPractice: {}, onStart: {})
        header.hideLivePollGate()
        #expect(header.isShowingLivePollGate == false)
        #expect(header.isUserInteractionEnabled == false)
    }

    @Test func gateIconSitsAboveHeroCenter() {
        let header = makeHeader()
        header.showLivePollGate(title: "Session 1", onPractice: {}, onStart: {})
        header.layoutIfNeeded()
        let icon = header.livePollGateIconView
        #expect(icon != nil)
        #expect((icon?.frame.midY ?? 0) < header.bounds.midY)
    }

    private func makeHeader() -> LiveHeaderView {
        let header = LiveHeaderView(frame: .zero)
        header.translatesAutoresizingMaskIntoConstraints = true
        header.frame = CGRect(x: 0, y: 0, width: 320, height: 180)
        return header
    }
}
