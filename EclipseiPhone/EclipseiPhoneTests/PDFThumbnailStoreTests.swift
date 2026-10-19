//
//  PDFThumbnailStoreTests.swift
//  EclipseiPhoneTests
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  PDF tiles showed the generic document glyph instead of the first page: previews
//  live in Caches, iOS purged them, and nothing rebuilt them. These pin that a real
//  PDF renders a visible preview and that a purged one comes back on its own.
//

import Foundation
import Testing
import UIKit
@testable import EclipseiPhone

@MainActor
struct PDFThumbnailStoreTests {

    /// A one-page PDF filled solid red, so the preview's colour is easy to check.
    private func makeRedPDF() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).pdf")
        let bounds = CGRect(x: 0, y: 0, width: 612, height: 792)
        let data = UIGraphicsPDFRenderer(bounds: bounds).pdfData { context in
            context.beginPage()
            UIColor.red.setFill()
            context.fill(bounds)
        }
        try data.write(to: url)
        return url
    }

    /// RGBA of the pixel at the image's centre.
    private func centerPixel(of image: UIImage) throws -> (r: UInt8, g: UInt8, b: UInt8) {
        let cgImage = try #require(image.cgImage)
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = try #require(CGContext(
            data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        let x = CGFloat(cgImage.width) / 2
        let y = CGFloat(cgImage.height) / 2
        context.draw(cgImage, in: CGRect(
            x: -x, y: -y, width: CGFloat(cgImage.width), height: CGFloat(cgImage.height)
        ))
        return (pixel[0], pixel[1], pixel[2])
    }

    private func scratchDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("PDFThumbnailStoreTests.\(UUID().uuidString)")
    }

    private func waitForImage(_ id: UUID, in store: PDFThumbnailStore) async -> UIImage? {
        for _ in 0..<100 {
            if let image = store.image(for: id) { return image }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return nil
    }

    @Test func generateRendersFirstPage() async throws {
        let pdf = try makeRedPDF()
        let root = scratchDirectory()
        let id = UUID()
        defer {
            try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: root)
        }
        let store = PDFThumbnailStore(rootDirectory: root, pdfURL: { _ in nil })

        store.generate(from: pdf, for: id)

        let image = try #require(await waitForImage(id, in: store))
        let pixel = try centerPixel(of: image)
        #expect(pixel.r > 200 && pixel.g < 60 && pixel.b < 60)
    }

    /// The bug on device: the PDF is saved, but iOS emptied Caches. Reading the
    /// preview must rebuild it rather than leave the tile on the glyph forever.
    @Test func purgedPreviewIsRebuiltFromSavedPDF() async throws {
        let pdf = try makeRedPDF()
        let root = scratchDirectory()
        let id = UUID()
        defer {
            try? FileManager.default.removeItem(at: pdf)
            try? FileManager.default.removeItem(at: root)
        }
        let store = PDFThumbnailStore(rootDirectory: root, pdfURL: { $0 == id ? pdf : nil })
        // Simulate the purge: the whole folder is gone.
        try FileManager.default.removeItem(at: root)

        #expect(store.image(for: id) == nil)

        let image = try #require(await waitForImage(id, in: store))
        let pixel = try centerPixel(of: image)
        #expect(pixel.r > 200 && pixel.g < 60 && pixel.b < 60)
    }

    @Test func unknownIdDoesNotRebuild() {
        let root = scratchDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        var lookups = 0
        let store = PDFThumbnailStore(rootDirectory: root, pdfURL: { _ in
            lookups += 1
            return nil
        })

        #expect(store.image(for: UUID()) == nil)
        #expect(lookups == 1)
    }
}
