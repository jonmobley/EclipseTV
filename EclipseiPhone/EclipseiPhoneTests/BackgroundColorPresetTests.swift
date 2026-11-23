//
//  BackgroundColorPresetTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Testing
import UIKit
@testable import EclipseiPhone

/// The Background color presets must stay identical to the Mac's
/// `BackgroundGradientPreset` (names, order, colors, virtual URL).
struct BackgroundColorPresetTests {

    @Test func sameEightPresetsInTheMacOrder() {
        #expect(BackgroundColorPreset.allCases.map(\.rawValue) == [
            "azure", "seafoam", "magentaCoral", "warmEmber",
            "blueLavender", "paleSand", "black", "white"
        ])
        #expect(BackgroundColorPreset.allCases.map(\.title) == [
            "Azure", "Seafoam", "Magenta Coral", "Warm Ember",
            "Blue Lavender", "Pale Sand", "Black", "White"
        ])
    }

    @Test func colorStopsMatchTheMac() {
        typealias RGB = BackgroundColorPreset.RGB
        #expect(BackgroundColorPreset.azure.rgbStops == [RGB(0.10, 0.18, 0.42), RGB(0.28, 0.52, 0.82)])
        #expect(BackgroundColorPreset.seafoam.rgbStops == [RGB(0.45, 0.72, 0.68), RGB(0.78, 0.90, 0.82)])
        #expect(BackgroundColorPreset.magentaCoral.rgbStops == [RGB(0.55, 0.18, 0.55), RGB(0.95, 0.55, 0.58)])
        #expect(BackgroundColorPreset.warmEmber.rgbStops == [RGB(0.92, 0.58, 0.32), RGB(0.82, 0.38, 0.42)])
        #expect(BackgroundColorPreset.blueLavender.rgbStops == [
            RGB(0.35, 0.48, 0.78), RGB(0.62, 0.58, 0.88), RGB(0.72, 0.82, 0.95)
        ])
        #expect(BackgroundColorPreset.paleSand.rgbStops == [
            RGB(0.94, 0.93, 0.90), RGB(0.88, 0.86, 0.82), RGB(0.82, 0.84, 0.86)
        ])
        #expect(BackgroundColorPreset.black.rgbStops == [RGB(0, 0, 0), RGB(0, 0, 0)])
        #expect(BackgroundColorPreset.white.rgbStops == [RGB(1, 1, 1), RGB(1, 1, 1)])
    }

    @Test func virtualURLRoundTrips() throws {
        for preset in BackgroundColorPreset.allCases {
            #expect(preset.url.absoluteString == "eclipse://builtin/gradient/\(preset.rawValue)")
            #expect(BackgroundColorPreset(url: preset.url) == preset)
        }
        #expect(BackgroundColorPreset(url: try #require(URL(string: "eclipse://builtin/gradient/neon"))) == nil)
        #expect(BackgroundColorPreset(url: try #require(URL(string: "eclipse://builtin/image/azure"))) == nil)
        #expect(BackgroundColorPreset(url: try #require(URL(string: "https://builtin/gradient/azure"))) == nil)
        #expect(BackgroundColorPreset(url: URL(fileURLWithPath: "/tmp/gradient/azure")) == nil)
    }

    @Test func savedNameReadsBackAndUnknownNamesReadAsNone() {
        #expect(BackgroundColorPreset(savedName: "warmEmber") == .warmEmber)
        #expect(BackgroundColorPreset(savedName: "somethingNewer") == nil)
        #expect(BackgroundColorPreset(savedName: nil) == nil)
    }

    @Test func pictureIsStageSizedAndOpaque() throws {
        let image = BackgroundColorPreset.azure.image()
        let cgImage = try #require(image.cgImage)
        #expect(cgImage.width == 1920)
        #expect(cgImage.height == 1080)
        #expect([.none, .noneSkipFirst, .noneSkipLast].contains(cgImage.alphaInfo))
    }

    @Test func gradientRunsFromTopLeftToBottomRight() throws {
        for preset in BackgroundColorPreset.allCases {
            let image = preset.image(size: CGSize(width: 160, height: 90))
            let stops = preset.rgbStops
            let first = try #require(stops.first)
            let last = try #require(stops.last)
            expectClose(try pixel(of: image, x: 0, y: 0), first, "\(preset) top-left")
            expectClose(try pixel(of: image, x: 159, y: 89), last, "\(preset) bottom-right")
        }
    }

    @Test func swatchKeepsItsOwnColors() {
        let swatch = BackgroundColorPreset.white.swatch()
        #expect(swatch.renderingMode == .alwaysOriginal)
        #expect(swatch.size == CGSize(width: 28, height: 28))
    }

    // MARK: - Helpers

    private func expectClose(
        _ actual: BackgroundColorPreset.RGB,
        _ expected: BackgroundColorPreset.RGB,
        _ label: String
    ) {
        let tolerance: CGFloat = 0.03
        #expect(abs(actual.red - expected.red) < tolerance, "\(label) red")
        #expect(abs(actual.green - expected.green) < tolerance, "\(label) green")
        #expect(abs(actual.blue - expected.blue) < tolerance, "\(label) blue")
    }

    /// Reads one pixel by redrawing the image into a known sRGB RGBA buffer.
    private func pixel(of image: UIImage, x: Int, y: Int) throws -> BackgroundColorPreset.RGB {
        let cgImage = try #require(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var data = [UInt8](repeating: 0, count: width * height * 4)
        let space = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let context = try #require(CGContext(
            data: &data, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: space,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
        // Buffer rows run top to bottom, matching UIKit's y.
        let offset = (y * width + x) * 4
        return BackgroundColorPreset.RGB(
            CGFloat(data[offset]) / 255,
            CGFloat(data[offset + 1]) / 255,
            CGFloat(data[offset + 2]) / 255
        )
    }
}
