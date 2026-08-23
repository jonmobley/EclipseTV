//
//  CameraMirrorLayoutTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

struct CameraMirrorLayoutTests {

    @Test func quarterTurnSwapsDimensions() {
        #expect(PresentationViewController.rotationSwapsDimensions(90))
        #expect(PresentationViewController.rotationSwapsDimensions(270))
        #expect(PresentationViewController.rotationSwapsDimensions(-90))
        #expect(PresentationViewController.rotationSwapsDimensions(0) == false)
        #expect(PresentationViewController.rotationSwapsDimensions(180) == false)
    }

    @Test func landscapePanelStaysWidescreenAfter90DegreeMirror() {
        let panel = CGSize(width: 320, height: 180)
        let content = PresentationViewController.rotatedContentSize(
            for: panel,
            rotationDegrees: 90
        )
        #expect(content == CGSize(width: 180, height: 320))
        let visible = CGSize(width: content.height, height: content.width)
        #expect(visible == panel)
        #expect(abs(visible.width / visible.height - 16.0 / 9.0) < 0.001)
    }

    @Test func halfTurnKeepsLandscapeSize() {
        let panel = CGSize(width: 320, height: 180)
        let content = PresentationViewController.rotatedContentSize(
            for: panel,
            rotationDegrees: 180
        )
        #expect(content == panel)
    }

    @Test @MainActor func ninetyDegreeMirrorFillsSixteenByNinePanel() {
        let container = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        let content = UIView()
        container.addSubview(content)
        PresentationViewController.applyRotatedLayout(
            to: content,
            in: container,
            scale: 1,
            rotationDegrees: 90
        )
        let frame = content.convert(content.bounds, to: container)
        #expect(abs(frame.width - 320) < 0.5)
        #expect(abs(frame.height - 180) < 0.5)
    }
}
