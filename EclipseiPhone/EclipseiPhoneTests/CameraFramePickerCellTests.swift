//
//  CameraFramePickerCellTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// The ⋯ on a Camera Frames thumbnail must receive taps (it sits inside an image view,
/// which ignores touches unless told otherwise).
@MainActor
struct CameraFramePickerCellTests {

    @Test func moreButtonReceivesTaps() throws {
        let cell = CameraFramePickerCell(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        cell.configureFrame(image: nil, selected: true, moreMenu: UIMenu(children: []))
        cell.layoutIfNeeded()

        // Centre of the 28pt pill: 8pt in from the thumb's top-right corner.
        let point = CGPoint(x: 200 - 8 - 14, y: 8 + 14)
        let hit = try #require(cell.hitTest(point, with: nil))
        // The menu button takes taps through its own inner touch area.
        let button = sequence(first: hit, next: \.superview)
            .first { $0 is ScrollSafeMenuButton }
        #expect(button?.accessibilityLabel == "More")
    }

    @Test func restOfCardStillSelects() throws {
        let cell = CameraFramePickerCell(frame: CGRect(x: 0, y: 0, width: 200, height: 150))
        cell.configureFrame(image: nil, selected: false, moreMenu: UIMenu(children: []))
        cell.layoutIfNeeded()

        let hit = try #require(cell.hitTest(CGPoint(x: 40, y: 80), with: nil))
        #expect(!(hit is UIControl))
    }
}
