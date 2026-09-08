//
//  AspectCropGeometryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Round-trips the framing editor's scroll geometry so a saved crop reopens and
/// re-saves as the same region instead of drifting toward the image's top-left.
@Suite(.serialized)
@MainActor
struct AspectCropGeometryTests {

    @Test func restoredFramingSavesAsTheSameRect() throws {
        let initial = CGRect(x: 200, y: 300, width: 800, height: 450)
        let (controller, window) = makeLaidOutCropper(initialCropRect: initial)
        defer { window.isHidden = true }

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, initial)
    }

    @Test func fullWidthFramingNearTopSavesAsTheSameRect() throws {
        // Reproduces the reported case: a portrait photo framed high (face near the
        // top) where the scroll offset is negative relative to the top inset.
        let initial = CGRect(x: 0, y: 160, width: 1200, height: 675)
        let (controller, window) = makeLaidOutCropper(initialCropRect: initial)
        defer { window.isHidden = true }

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, initial)
    }

    @Test func defaultFramingIsCenteredAtTargetAspect() throws {
        let (controller, window) = makeLaidOutCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        let saved = try #require(controller.visibleCropRectInImage())
        let imageSize = controller.sourceImage.size
        let expectedHeight = imageSize.width / MediaAspect.landscape
        let expected = CGRect(
            x: 0,
            y: (imageSize.height - expectedHeight) / 2,
            width: imageSize.width,
            height: expectedHeight
        )
        expectClose(saved, expected)
    }

    // MARK: - Helpers

    private func makeLaidOutCropper(
        initialCropRect: CGRect?
    ) -> (AspectCropViewController, UIWindow) {
        let controller = AspectCropViewController(
            image: portraitImage(),
            targetAspect: MediaAspect.landscape,
            confirmTitle: "Save"
        )
        controller.initialCropRect = initialCropRect
        controller.onFramingChosen = { _ in }

        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = controller
        window.makeKeyAndVisible()
        controller.view.layoutIfNeeded()
        return (controller, window)
    }

    private func portraitImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let size = CGSize(width: 1200, height: 1600)
        return UIGraphicsImageRenderer(size: size, format: format).image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func expectClose(
        _ actual: CGRect,
        _ expected: CGRect,
        tolerance: CGFloat = 1.5,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            abs(actual.minX - expected.minX) <= tolerance,
            "minX \(actual.minX) vs \(expected.minX)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.minY - expected.minY) <= tolerance,
            "minY \(actual.minY) vs \(expected.minY)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.width - expected.width) <= tolerance,
            "width \(actual.width) vs \(expected.width)",
            sourceLocation: sourceLocation
        )
        #expect(
            abs(actual.height - expected.height) <= tolerance,
            "height \(actual.height) vs \(expected.height)",
            sourceLocation: sourceLocation
        )
    }
}
