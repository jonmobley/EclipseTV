//
//  AspectCropGeometryTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// Pins the framing editor's saved rect to what is actually visible through the crop
/// window. The round-trip cases alone would pass with a shared wrong assumption, so
/// `renderedWindowShowsTheSavedRegion` samples rendered pixels as ground truth.
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

    /// After an arbitrary pinch and pan, UIKit's conversion must agree with the
    /// offset / zoom arithmetic. Either side being wrong shows up here.
    @Test func savedRectAgreesWithScrollMath() throws {
        let (controller, window) = makeLaidOutCropper(initialCropRect: nil)
        defer { window.isHidden = true }
        let scroll = controller.scrollView
        scroll.zoomScale = scroll.minimumZoomScale * 2.3
        scroll.contentOffset = CGPoint(x: 120, y: 300)

        let zoom = scroll.zoomScale
        let frame = controller.cropFrameView.frame.offsetBy(
            dx: -scroll.frame.minX, dy: -scroll.frame.minY
        )
        let expected = CGRect(
            x: (frame.minX + scroll.contentOffset.x) / zoom,
            y: (frame.minY + scroll.contentOffset.y) / zoom,
            width: frame.width / zoom,
            height: frame.height / zoom
        )
        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, expected)
    }

    /// Ground truth: the pixels drawn inside the window must come from the saved rect.
    /// The source encodes x in red and y in green, so a sample's colour is its position.
    @Test func renderedWindowShowsTheSavedRegion() throws {
        let imageSize = CGSize(width: 600, height: 800)
        let (controller, window) = makeLaidOutCropper(
            image: positionEncodedImage(size: imageSize),
            initialCropRect: CGRect(x: 90, y: 250, width: 400, height: 225)
        )
        defer { window.isHidden = true }
        let scroll = controller.scrollView
        scroll.zoomScale = scroll.minimumZoomScale * 1.7
        scroll.contentOffset = CGPoint(
            x: scroll.contentOffset.x + 37, y: scroll.contentOffset.y - 21
        )
        controller.dimView.isHidden = true
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, controller.cropWindowInImageSpace(), tolerance: 0.01)
        let shot = render(controller.view)
        let cropFrame = controller.cropFrameView.frame
        let inset: CGFloat = 8
        for (u, v) in [(0.0, 0.0), (0.5, 0.5), (1.0, 1.0), (0.0, 1.0), (1.0, 0.0)] {
            let point = CGPoint(
                x: cropFrame.minX + inset + (cropFrame.width - 2 * inset) * u,
                y: cropFrame.minY + inset + (cropFrame.height - 2 * inset) * v
            )
            let colour = try #require(pixel(in: shot, at: point))
            let expectedX = saved.minX + (point.x - cropFrame.minX) / scroll.zoomScale
            let expectedY = saved.minY + (point.y - cropFrame.minY) / scroll.zoomScale
            let unitX = expectedX / (imageSize.width - 1)
            let unitY = expectedY / (imageSize.height - 1)
            #expect(abs(colour.r - unitX) < 0.03, "x at (\(u), \(v)): \(colour.r) vs \(unitX)")
            #expect(abs(colour.g - unitY) < 0.03, "y at (\(u), \(v)): \(colour.g) vs \(unitY)")
            #expect(abs(colour.b - 128 / 255) < 0.03, "window is dimmed or blank")
        }
    }

    /// A late size change (safe area, size class) must re-derive the zoom floor and
    /// insets without moving the framing the user already has.
    @Test func windowResizeAfterConfigurePreservesFraming() throws {
        let initial = CGRect(x: 200, y: 300, width: 800, height: 450)
        let (controller, window) = makeLaidOutCropper(initialCropRect: initial)
        defer { window.isHidden = true }

        window.frame = CGRect(x: 0, y: 0, width: 430, height: 932)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, initial)
        let scroll = controller.scrollView
        let floor = controller.cropFrameView.frame.width / controller.sourceImage.size.width
        #expect(abs(scroll.minimumZoomScale - floor) < 0.001)
    }

    /// A taller view keeps the crop window's size but moves it, so the insets must
    /// follow the window even though the zoom floor does not change.
    @Test func windowMoveWithoutResizeRefreshesInsets() throws {
        let initial = CGRect(x: 200, y: 300, width: 800, height: 450)
        let (controller, window) = makeLaidOutCropper(initialCropRect: initial)
        defer { window.isHidden = true }
        let scroll = controller.scrollView
        let insetsBefore = scroll.contentInset

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 932)
        controller.view.frame = window.bounds
        controller.view.layoutIfNeeded()

        let windowTop = controller.cropFrameView.frame.minY - scroll.frame.minY
        #expect(abs(scroll.contentInset.top - windowTop) < 0.5)
        #expect(abs(scroll.contentInset.top - insetsBefore.top) > 10)
        let saved = try #require(controller.visibleCropRectInImage())
        expectClose(saved, initial)
    }

    // MARK: - Helpers

    private func makeLaidOutCropper(
        image: UIImage? = nil,
        initialCropRect: CGRect?
    ) -> (AspectCropViewController, UIWindow) {
        let controller = AspectCropViewController(
            image: image ?? portraitImage(),
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

    /// RGBA bitmap where red ramps with x, green with y, and blue is a constant 128.
    private func positionEncodedImage(size: CGSize) -> UIImage {
        let width = Int(size.width)
        let height = Int(size.height)
        var pixels = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let i = (y * width + x) * 4
                pixels[i] = UInt8(255 * x / (width - 1))
                pixels[i + 1] = UInt8(255 * y / (height - 1))
                pixels[i + 2] = 128
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let cgImage = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        )!
        return UIImage(cgImage: cgImage)
    }

    /// Renders the layer tree at 1× so pixel coordinates equal view points.
    private func render(_ view: UIView) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(bounds: view.bounds, format: format).image { ctx in
            view.layer.render(in: ctx.cgContext)
        }
    }

    /// Samples one pixel through a known-format 1×1 context so the source bitmap
    /// layout does not matter.
    private func pixel(
        in image: UIImage,
        at point: CGPoint
    ) -> (r: CGFloat, g: CGFloat, b: CGFloat)? {
        guard let cgImage = image.cgImage else { return nil }
        let x = Int(point.x.rounded(.down))
        let y = Int(point.y.rounded(.down))
        var sample = [UInt8](repeating: 0, count: 4)
        let drawn = sample.withUnsafeMutableBytes { buffer -> Bool in
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
            context.draw(cgImage, in: CGRect(
                x: -CGFloat(x),
                y: -CGFloat(cgImage.height - 1 - y),
                width: CGFloat(cgImage.width),
                height: CGFloat(cgImage.height)
            ))
            return true
        }
        guard drawn else { return nil }
        return (CGFloat(sample[0]) / 255, CGFloat(sample[1]) / 255, CGFloat(sample[2]) / 255)
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
