//
//  AspectCropFidelityTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Checks the saved framing against the pixels the editor actually shows inside the
/// crop window, instead of re-deriving the geometry a second way.
///
/// The source image is a gradient: red rises with x, green with y, so a sampled colour
/// reports the position it came from. Comparing samples from the saved crop against the
/// same points of a render of the crop window catches the failure that shipped — a
/// correctly shaped rect taken from the wrong part of the photo.
@Suite(.serialized)
@MainActor
struct AspectCropFidelityTests {

    @Test func zoomedFramingSavesThePixelsInsideTheWindow() throws {
        let (controller, window) = makeCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        let scrollView = controller.scrollView
        scrollView.zoomScale = fillZoom(of: controller) * 2.2
        scrollView.contentOffset = CGPoint(x: 150, y: 500)

        try expectSavedFramingMatchesWindow(in: controller)
    }

    @Test func restoredFramingSavesThePixelsInsideTheWindow() throws {
        let (controller, window) = makeCropper(
            initialCropRect: CGRect(x: 120, y: 640, width: 900, height: 506)
        )
        defer { window.isHidden = true }

        try expectSavedFramingMatchesWindow(in: controller)
    }

    @Test func framingStaysPutWhileSafeAreaInsetsSettle() throws {
        // A presented cropper lays out several times on the way in as its safe-area
        // insets arrive. Each pass moves the crop window, and re-reading the framing
        // afterwards used to hand back the region behind the window's new position —
        // a drift that compounded per pass until it hit an edge.
        let initial = CGRect(x: 0, y: 820, width: 1200, height: 675)
        let (controller, window) = makeCropper(initialCropRect: initial)
        defer { window.isHidden = true }

        for top in [10.0, 24.0, 40.0, 59.0] {
            controller.additionalSafeAreaInsets = UIEdgeInsets(
                top: top, left: 0, bottom: top / 2, right: 0
            )
            controller.view.layoutIfNeeded()
        }

        let saved = try #require(controller.visibleCropRectInImage())
        #expect(abs(saved.minY - initial.minY) <= 2, "minY \(saved.minY)")
        #expect(abs(saved.height - initial.height) <= 2, "height \(saved.height)")
        try expectSavedFramingMatchesWindow(in: controller)
    }

    @Test func zoomViewOfTheWrongShapeStillSavesWhatTheWindowShows() throws {
        // The mapping used to assume the zoom view's bounds *are* the photo. If anything
        // ever gives the zoom view a different shape, `.scaleAspectFit` letterboxes the
        // photo inside it, and a mapping through the bounds reads the wrong region.
        let (controller, window) = makeCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        let scrollView = controller.scrollView
        controller.imageView.bounds = CGRect(x: 0, y: 0, width: 1200, height: 2200)
        scrollView.zoomScale = fillZoom(of: controller) * 2
        let cropWindow = controller.cropWindowInScrollFrame()
        let content = controller.imageView.frame
        scrollView.contentOffset = CGPoint(
            x: content.midX - cropWindow.midX,
            y: content.midY - cropWindow.midY
        )

        try expectSavedFramingMatchesWindow(in: controller)
    }

    @Test func fitFramingSlidAsideSavesThePhotoAndTheBarWhereTheyShow() throws {
        // Zoomed out to Fit and nudged to one side: the saved bitmap has the photo where
        // the window shows it and black where the window shows the scroll view behind.
        let (controller, window) = makeCropper(initialCropRect: nil)
        defer { window.isHidden = true }

        let scrollView = controller.scrollView
        scrollView.zoomScale = scrollView.minimumZoomScale
        controller.view.layoutIfNeeded()
        let cropWindow = controller.cropWindowInScrollFrame()
        let content = scrollView.contentSize
        let slack = cropWindow.width - content.width
        #expect(slack > 20, "portrait photo at Fit leaves room at the sides")
        // Centered, then nudged a third of the slack: still inside the allowed travel.
        scrollView.contentOffset = CGPoint(
            x: content.width / 2 - cropWindow.midX + slack / 3,
            y: content.height / 2 - cropWindow.midY
        )
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        #expect(saved.minX < -1)
        #expect(saved.maxX > controller.sourceImage.size.width + 1)
        try expectSavedFramingMatchesWindow(in: controller)

        let framed = try #require(MediaAspect.framed(controller.sourceImage, to: saved))
        let leftBar = try #require(sample(framed, 0.02, 0.5))
        #expect(leftBar.allSatisfy { $0 <= 10 }, "left edge is a bar: \(leftBar)")
    }

    @Test func savedFramingShowsTheSameRegionOnATile() throws {
        // The seam the user actually sees: the editor saves a rect against the full
        // photo, and the grid applies it to a tile-sized copy of the same photo.
        let id = "framing-fidelity-\(UUID().uuidString)"
        defer { MediaFramingStore.clear(forId: id) }
        let (controller, window) = makeCropper(
            initialCropRect: CGRect(x: 200, y: 700, width: 900, height: 506)
        )
        defer { window.isHidden = true }

        let saved = try #require(controller.visibleCropRectInImage())
        MediaFramingStore.set(
            MediaFraming(rect: saved, in: controller.sourceImage.size), forId: id
        )
        // The tile resolves the framing against the *active* Display Mode, so pin it to
        // the mode this cropper was built for.
        let framed = ExternalOutputOrientationFixture.with(.landscape) {
            MediaFramingStore.framedStill(
                ThumbnailDecoder.downsample(controller.sourceImage),
                forId: id,
                fallback: .scaleAspectFill
            )
        }
        let tile = try #require(framed.image)
        #expect(framed.contentMode == .scaleAspectFit)
        #expect(
            abs(tile.size.width / tile.size.height - MediaAspect.landscape) < 0.05,
            "tile \(tile.size)"
        )

        let shown = renderCropWindow(in: controller)
        for fx in [0.25, 0.75] {
            for fy in [0.25, 0.75] {
                let onTile = try #require(sample(tile, fx, fy))
                let inEditor = try #require(sample(shown, fx, fy))
                #expect(
                    close(onTile, inEditor),
                    "at (\(fx), \(fy)) tile \(onTile) vs editor \(inEditor)"
                )
            }
        }
    }

    // MARK: - Helpers

    /// Zoom at which the photo exactly covers the crop window (Fill).
    private func fillZoom(of controller: AspectCropViewController) -> CGFloat {
        let crop = controller.cropFrameView.frame
        let imageSize = controller.sourceImage.size
        return max(crop.width / imageSize.width, crop.height / imageSize.height)
    }

    private func expectSavedFramingMatchesWindow(
        in controller: AspectCropViewController,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let saved = try #require(controller.visibleCropRectInImage())
        let cropped = try #require(MediaAspect.framed(controller.sourceImage, to: saved))
        let shown = renderCropWindow(in: controller)

        for fx in [0.15, 0.5, 0.85] {
            for fy in [0.15, 0.5, 0.85] {
                let expected = try #require(sample(cropped, fx, fy))
                let actual = try #require(sample(shown, fx, fy))
                #expect(
                    close(expected, actual),
                    "at (\(fx), \(fy)) saved \(expected) vs shown \(actual), rect \(saved)",
                    sourceLocation: sourceLocation
                )
            }
        }
    }

    /// Renders what the user sees inside the white box, chrome hidden.
    private func renderCropWindow(in controller: AspectCropViewController) -> UIImage {
        let crop = controller.cropFrameView.frame
        controller.dimView.isHidden = true
        controller.cropFrameView.isHidden = true
        defer {
            controller.dimView.isHidden = false
            controller.cropFrameView.isHidden = false
        }
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: crop.size, format: format).image { ctx in
            ctx.cgContext.translateBy(x: -crop.minX, y: -crop.minY)
            controller.view.layer.render(in: ctx.cgContext)
        }
    }

    /// Red / green / blue at a relative point of `image`.
    private func sample(_ image: UIImage, _ fx: CGFloat, _ fy: CGFloat) -> [UInt8]? {
        guard let source = image.cgImage else { return nil }
        let x = Int((CGFloat(source.width) - 1) * fx)
        let y = Int((CGFloat(source.height) - 1) * fy)
        var pixel = [UInt8](repeating: 0, count: 4)
        let drawn = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .none
            context.draw(
                source,
                in: CGRect(
                    x: CGFloat(-x),
                    y: CGFloat(-(source.height - 1 - y)),
                    width: CGFloat(source.width),
                    height: CGFloat(source.height)
                )
            )
            return true
        }
        return drawn ? Array(pixel.prefix(3)) : nil
    }

    /// Within ~4% of a channel: the gradient turns that into ~50 points of the photo,
    /// loose enough for resampling and tight enough to catch a misplaced crop.
    private func close(_ lhs: [UInt8], _ rhs: [UInt8]) -> Bool {
        zip(lhs, rhs).allSatisfy { abs(Int($0) - Int($1)) <= 10 }
    }

    private func makeCropper(
        initialCropRect: CGRect?
    ) -> (AspectCropViewController, UIWindow) {
        let controller = AspectCropViewController(
            image: gradientImage(width: 1200, height: 1600),
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

    /// Red rises left to right, green top to bottom, so colour encodes position.
    private func gradientImage(width: Int, height: Int) -> UIImage {
        let bytesPerRow = width * 4
        var bytes = [UInt8](repeating: 255, count: bytesPerRow * height)
        for y in 0..<height {
            let green = UInt8(255 * y / max(height - 1, 1))
            for x in 0..<width {
                let index = y * bytesPerRow + x * 4
                bytes[index] = UInt8(255 * x / max(width - 1, 1))
                bytes[index + 1] = green
                bytes[index + 2] = 96
            }
        }
        let image = bytes.withUnsafeMutableBytes { buffer -> CGImage? in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return nil }
            return context.makeImage()
        }
        guard let image else { return UIImage() }
        return UIImage(cgImage: image, scale: 1, orientation: .up)
    }
}
