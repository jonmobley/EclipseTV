//
//  OverlayQRCodeImage.swift
//  Eclipse (iPhone/iPad port of the Mac's QRCodeImage)
//
//  Description: Core Image QR-code rasterizer for the QR Code template card.
//  Thread Safety: Pure functions - safe from any thread. CIContext work is
//                 synchronous and not cached.
//

import CoreImage.CIFilterBuiltins
import UIKit

// MARK: - OverlayQRCodeImage

/// Builds a `UIImage` QR code from a UTF-8 payload string.
enum OverlayQRCodeImage {

    // MARK: - Constants

    /// Module upscale before rasterizing so the bitmap stays crisp when drawn large.
    private static let moduleScale: CGFloat = 10

    // MARK: - Public Interface

    /// Renders a QR code for `string` at the given point size.
    ///
    /// - Parameters:
    ///   - string: Payload encoded in the QR (URL, text, etc.).
    ///   - side: Width and height of the returned image in points.
    /// - Returns: A sharp QR image, or nil when the string is empty or
    ///   Core Image fails to produce output.
    static func make(from string: String, side: CGFloat) -> UIImage? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, side > 0 else { return nil }

        let context = CIContext()
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(trimmed.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }

        let scaled = output.transformed(
            by: CGAffineTransform(scaleX: moduleScale, y: moduleScale)
        )
        guard let cgImage = context.createCGImage(scaled, from: scaled.extent) else {
            return nil
        }
        return UIImage(cgImage: cgImage)
    }
}
