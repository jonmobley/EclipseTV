//
//  PresentationImageDecoderTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit
import Testing
@testable import EclipseiPhone

struct PresentationImageDecoderTests {

    @Test func maxPixelEdgeUsesNativeBounds() {
        // Without a live external screen, fallback is 1080p long edge.
        #expect(
            PresentationImageDecoder.maxPixelEdge(for: nil)
                == PresentationImageDecoder.fallbackMaxPixelEdge
        )
    }

    @Test func decodeBoundsLongestEdge() throws {
        let size = CGSize(width: 4000, height: 3000)
        let url = try writeJPEG(size: size)
        defer { try? FileManager.default.removeItem(at: url) }

        let maxEdge = 1920
        let image = try #require(
            PresentationImageDecoder.decode(fileURL: url, maxPixelEdge: maxEdge)
        )
        let longest = max(
            image.size.width * image.scale,
            image.size.height * image.scale
        )
        #expect(longest <= CGFloat(maxEdge) + 1)
    }

    @Test func decodeReturnsNilForMissingFile() {
        let url = URL(fileURLWithPath: "/tmp/does-not-exist-\(UUID().uuidString).jpg")
        #expect(PresentationImageDecoder.decode(fileURL: url, maxPixelEdge: 640) == nil)
    }

    @Test func fillDecodesPortraitToCoverThePanelAtNativeDensity() throws {
        // 3000×4000 covering 1920×1080 shows 1920×2560; the old screen-edge cap gave
        // 1440×1920 and let `.scaleAspectFill` magnify it 1.33×.
        let url = try writeJPEG(size: CGSize(width: 3000, height: 4000))
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(PresentationImageDecoder.decode(
            fileURL: url,
            panelPixelSize: CGSize(width: 1920, height: 1080),
            placement: .fill
        ))
        #expect(abs(pixelSize(of: image).width - 1920) <= 1)
        #expect(abs(pixelSize(of: image).height - 2560) <= 1)
    }

    @Test func fitDecodesPortraitToThePanelHeight() throws {
        let url = try writeJPEG(size: CGSize(width: 3000, height: 4000))
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(PresentationImageDecoder.decode(
            fileURL: url,
            panelPixelSize: CGSize(width: 1920, height: 1080),
            placement: .fit
        ))
        #expect(abs(pixelSize(of: image).height - 1080) <= 1)
    }

    @Test func cropDecodesEnoughForTheCroppedRegion() throws {
        // A centered half-size window needs the whole 3840-wide file to reach 1920 px.
        let url = try writeJPEG(size: CGSize(width: 3840, height: 2160))
        defer { try? FileManager.default.removeItem(at: url) }

        let image = try #require(PresentationImageDecoder.decode(
            fileURL: url,
            panelPixelSize: CGSize(width: 1920, height: 1080),
            placement: .crop(CGRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5))
        ))
        #expect(abs(pixelSize(of: image).width - 3840) <= 1)
    }

    @Test func panelPixelSizeSwapsEdgesForVerticalRotation() {
        #expect(
            PresentationImageDecoder.panelPixelSize(for: nil, rotationDegrees: 0)
                == CGSize(width: 1920, height: 1080)
        )
        #expect(
            PresentationImageDecoder.panelPixelSize(for: nil, rotationDegrees: 90)
                == CGSize(width: 1080, height: 1920)
        )
        #expect(
            PresentationImageDecoder.panelPixelSize(for: nil, rotationDegrees: -90)
                == CGSize(width: 1080, height: 1920)
        )
        #expect(
            PresentationImageDecoder.panelPixelSize(for: nil, rotationDegrees: 180)
                == CGSize(width: 1920, height: 1080)
        )
    }

    @Test func placementPrefersACustomCropOverFill() {
        let framing = MediaFraming(x: 0.1, y: 0.2, width: 0.5, height: 0.5)
        #expect(
            PresentationImageDecoder.placement(fill: true, framing: framing)
                == .crop(CGRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5))
        )
        #expect(PresentationImageDecoder.placement(fill: true, framing: nil) == .fill)
        #expect(PresentationImageDecoder.placement(fill: false, framing: nil) == .fit)
    }

    private func pixelSize(of image: UIImage) -> CGSize {
        CGSize(width: image.size.width * image.scale, height: image.size.height * image.scale)
    }

    // MARK: - Helpers

    private func writeJPEG(size: CGSize) throws -> URL {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let image = renderer.image { context in
            UIColor.red.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
        let data = try #require(image.jpegData(compressionQuality: 0.9))
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("pres-decode-\(UUID().uuidString).jpg")
        try data.write(to: url)
        return url
    }
}
