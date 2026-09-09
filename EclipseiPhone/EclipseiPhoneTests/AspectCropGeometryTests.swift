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

    @Test func framingSurvivesSafeAreaInsetsSettling() throws {
        // The cropper is presented over full screen, so its safe-area insets arrive
        // after the first layout pass and the crop window moves on the way in.
        let initial = CGRect(x: 0, y: 900, width: 1200, height: 675)
        let (controller, window) = makeLaidOutCropper(initialCropRect: initial)
        defer { window.isHidden = true }

        controller.additionalSafeAreaInsets = UIEdgeInsets(
            top: 59, left: 0, bottom: 34, right: 0
        )
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, initial, tolerance: 2)
    }

    @Test func zoomedFramingMatchesWhatIsBehindTheWindow() throws {
        let (controller, window) = makeLaidOutCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        let scrollView = controller.scrollView
        scrollView.zoomScale = scrollView.minimumZoomScale * 2.5
        scrollView.contentOffset = CGPoint(x: 40, y: 260)
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, onScreenCropRect(in: controller), tolerance: 4)
    }

    @Test func framingScrolledPastTheEdgeKeepsTheTargetAspect() throws {
        let (controller, window) = makeLaidOutCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        // Shove the content well past its limit: the window can hang off the photo,
        // and trimming the overhang instead of moving it back saves a thin strip.
        let scrollView = controller.scrollView
        scrollView.contentOffset = CGPoint(x: 4000, y: 4000)
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        let imageSize = controller.sourceImage.size
        #expect(abs(saved.width / saved.height - MediaAspect.landscape) < 0.02)
        #expect(saved.minX >= -0.5)
        #expect(saved.minY >= -0.5)
        #expect(saved.maxX <= imageSize.width + 0.5)
        #expect(saved.maxY <= imageSize.height + 0.5)
    }

    @Test func strayStoredFramingReopensAtTheTargetAspect() throws {
        // A framing saved before this geometry was correct (or under the other Display
        // Mode) is not the window's shape; it should reopen around what it showed.
        let strip = CGRect(x: 0, y: 700, width: 1200, height: 200)
        let (controller, window) = makeLaidOutCropper(initialCropRect: strip)
        defer { window.isHidden = true }

        let saved = try #require(controller.visibleCropRectInImage())
        #expect(abs(saved.width / saved.height - MediaAspect.landscape) < 0.02)
        #expect(abs(saved.midY - strip.midY) <= 2)
    }

    // MARK: - Helpers

    /// Crop window mapped into image space from on-screen frames alone, independent of
    /// the controller's own scroll math.
    private func onScreenCropRect(in controller: AspectCropViewController) -> CGRect {
        let imageOnScreen = controller.view.convert(
            controller.imageView.bounds, from: controller.imageView
        )
        let crop = controller.cropFrameView.frame
        let imageSize = controller.sourceImage.size
        let scaleX = imageSize.width / imageOnScreen.width
        let scaleY = imageSize.height / imageOnScreen.height
        return CGRect(
            x: (crop.minX - imageOnScreen.minX) * scaleX,
            y: (crop.minY - imageOnScreen.minY) * scaleY,
            width: crop.width * scaleX,
            height: crop.height * scaleY
        )
    }

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
