//
//  WebThumbnailSettledSnapshotTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import XCTest
@testable import EclipseiPhone

/// A website preview must not be rendered while its card is mid-transition:
/// that saved a small card in the corner of a black picture (2026-11-13).
@MainActor
final class WebThumbnailSettledSnapshotTests: XCTestCase {

    func testViewOutsideWindowIsNotSettled() {
        let panel = UIView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
        XCTAssertFalse(WebThumbnailPrefetcher.isSettledOnScreen(panel))
    }

    func testFullSizePanelInWindowIsSettled() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let panel = UIView(frame: CGRect(x: 20, y: 40, width: 320, height: 180))
        window.addSubview(panel)
        XCTAssertTrue(WebThumbnailPrefetcher.isSettledOnScreen(panel))
    }

    func testScaledAncestorIsNotSettled() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let container = UIView(frame: window.bounds)
        let panel = UIView(frame: CGRect(x: 20, y: 40, width: 320, height: 180))
        container.addSubview(panel)
        window.addSubview(container)
        container.transform = CGAffineTransform(scaleX: 0.62, y: 0.62)
        XCTAssertFalse(WebThumbnailPrefetcher.isSettledOnScreen(panel))
    }

    func testAnimatingAncestorIsNotSettled() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        let container = UIView(frame: window.bounds)
        let panel = UIView(frame: CGRect(x: 20, y: 40, width: 320, height: 180))
        container.addSubview(panel)
        window.addSubview(container)
        container.layer.add(CABasicAnimation(keyPath: "position"), forKey: "slide")
        XCTAssertFalse(WebThumbnailPrefetcher.isSettledOnScreen(panel))
    }

    func testSizeMatchAllowsOnePointOfRounding() {
        XCTAssertTrue(WebThumbnailPrefetcher.onScreenSizeMatches(
            CGSize(width: 320.5, height: 180), bounds: CGSize(width: 320, height: 180)
        ))
        XCTAssertFalse(WebThumbnailPrefetcher.onScreenSizeMatches(
            CGSize(width: 198, height: 111), bounds: CGSize(width: 320, height: 180)
        ))
    }
}
