//
//  BackgroundColorPreset.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// The Mac app's Background color presets: six soft diagonal gradients plus
/// solid Black and White.
///
/// Names, order, color stops and the virtual URL mirror the Mac's
/// `BackgroundGradientPreset` (eclipsepro, `Media/BackgroundGradientPreset.swift`);
/// keep the two in step. On iPhone a chosen preset is drawn to a picture and
/// stored as the Background still (`LogoStore.apply(_:)`), so the tile, the
/// hero, AirPlay and the Apple TV all show it through the existing picture path.
enum BackgroundColorPreset: String, CaseIterable, Sendable {

    case azure
    case seafoam
    case magentaCoral
    case warmEmber
    case blueLavender
    case paleSand
    case black
    case white

    /// Name shown to the user (same as the Mac).
    var title: String {
        switch self {
        case .azure: return "Azure"
        case .seafoam: return "Seafoam"
        case .magentaCoral: return "Magenta Coral"
        case .warmEmber: return "Warm Ember"
        case .blueLavender: return "Blue Lavender"
        case .paleSand: return "Pale Sand"
        case .black: return "Black"
        case .white: return "White"
        }
    }

    /// sRGB stops in 0…1, top-left to bottom-right. Solids repeat one color.
    var rgbStops: [RGB] {
        switch self {
        case .azure:
            return [RGB(0.10, 0.18, 0.42), RGB(0.28, 0.52, 0.82)]
        case .seafoam:
            return [RGB(0.45, 0.72, 0.68), RGB(0.78, 0.90, 0.82)]
        case .magentaCoral:
            return [RGB(0.55, 0.18, 0.55), RGB(0.95, 0.55, 0.58)]
        case .warmEmber:
            return [RGB(0.92, 0.58, 0.32), RGB(0.82, 0.38, 0.42)]
        case .blueLavender:
            return [RGB(0.35, 0.48, 0.78), RGB(0.62, 0.58, 0.88), RGB(0.72, 0.82, 0.95)]
        case .paleSand:
            return [RGB(0.94, 0.93, 0.90), RGB(0.88, 0.86, 0.82), RGB(0.82, 0.84, 0.86)]
        case .black:
            return [RGB(0, 0, 0), RGB(0, 0, 0)]
        case .white:
            return [RGB(1, 1, 1), RGB(1, 1, 1)]
        }
    }

    /// One sRGB color stop.
    struct RGB: Equatable, Sendable {
        let red: CGFloat
        let green: CGFloat
        let blue: CGFloat

        init(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat) {
            self.red = red
            self.green = green
            self.blue = blue
        }
    }

    /// Reads a saved preset name; unknown names (a newer build's preset) read as none.
    init?(savedName: String?) {
        guard let savedName else { return nil }
        self.init(rawValue: savedName)
    }

    // MARK: - Mac virtual URL

    /// The Mac's virtual URL for this preset (`eclipse://builtin/gradient/<rawValue>`).
    var url: URL {
        URL(string: "eclipse://builtin/gradient/\(rawValue)")!
    }

    /// Parses a preset from the Mac's virtual URL, or nil for any other URL.
    init?(url: URL) {
        guard url.scheme == "eclipse", url.host == "builtin" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count >= 2, parts[0] == "gradient" else { return nil }
        self.init(rawValue: parts[1])
    }

    // MARK: - Rendering

    /// Pixel size of the stored Background picture (same as the Mac's stage raster).
    static let stageSize = CGSize(width: 1920, height: 1080)

    /// The preset drawn as an opaque picture of `size` pixels.
    func image(size: CGSize = BackgroundColorPreset.stageSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        format.preferredRange = .standard
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            draw(in: CGRect(origin: .zero, size: size), context: context.cgContext)
        }
    }

    /// Small rounded chip for menus. Keeps its own colors (never tinted) and has
    /// a hairline edge so Black and White stay visible on any menu background.
    func swatch(side: CGFloat = 28) -> UIImage {
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            let shape = UIBezierPath(roundedRect: rect.insetBy(dx: 0.5, dy: 0.5), cornerRadius: side * 0.25)
            context.cgContext.saveGState()
            shape.addClip()
            draw(in: rect, context: context.cgContext)
            context.cgContext.restoreGState()
            UIColor.gray.withAlphaComponent(0.55).setStroke()
            shape.lineWidth = 1
            shape.stroke()
        }
        return image.withRenderingMode(.alwaysOriginal)
    }

    private func draw(in rect: CGRect, context: CGContext) {
        let space = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
        let colors = rgbStops.map {
            CGColor(srgbRed: $0.red, green: $0.green, blue: $0.blue, alpha: 1)
        }
        guard let gradient = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil) else {
            context.setFillColor(colors[0])
            context.fill(rect)
            return
        }
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: rect.minX, y: rect.minY),
            end: CGPoint(x: rect.maxX, y: rect.maxY),
            options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
        )
    }
}
