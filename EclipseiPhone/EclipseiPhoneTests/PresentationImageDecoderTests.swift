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
