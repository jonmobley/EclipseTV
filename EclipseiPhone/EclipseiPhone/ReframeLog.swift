//
//  ReframeLog.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import os
import UIKit

/// Console trace for the still-reframe path: editor open, editor Save, and the crop the
/// grid derives from what was saved.
///
/// Logged at error level so the lines survive Xcode's default console filtering and sit
/// next to the `ConnectionManager` output a Save already produces. Every line starts with
/// `[Reframe]` so a console search finds the whole story for one Save.
enum ReframeLog {
    private static let logger = Logger(subsystem: "com.eclipseapp.ios", category: "Reframe")

    /// Item whose tile / hero crops are traced; set by the last Save so grid reloads for
    /// every other still stay quiet.
    static var watchedId: String?

    static func emit(_ text: String) {
        logger.error("\(text, privacy: .public)")
    }

    /// One line per surface that crops `id`, only for the item just saved.
    static func logFramedStill(
        id: String,
        source: UIImage,
        crop: CGRect,
        result: UIImage?
    ) {
        guard id == watchedId else { return }
        emit(
            "[Reframe] TILE id=\(id) source \(image(source)) crop \(rect(crop)) "
            + "result \(image(result))"
        )
    }

    // MARK: - Formatting

    static func fmt(_ value: CGFloat) -> String {
        String(format: "%.1f", value)
    }

    static func fmt(_ value: Double) -> String {
        String(format: "%.4f", value)
    }

    static func rect(_ rect: CGRect) -> String {
        "(\(fmt(rect.minX)),\(fmt(rect.minY)) \(fmt(rect.width))×\(fmt(rect.height)))"
    }

    static func size(_ size: CGSize) -> String {
        "\(fmt(size.width))×\(fmt(size.height))"
    }

    static func insets(_ insets: UIEdgeInsets) -> String {
        "(t\(fmt(insets.top)) l\(fmt(insets.left)) b\(fmt(insets.bottom)) r\(fmt(insets.right)))"
    }

    static func image(_ image: UIImage?) -> String {
        guard let image else { return "nil" }
        let pixels = image.cgImage.map { "\($0.width)×\($0.height)px" } ?? "no cgImage"
        return "\(size(image.size))pt scale\(fmt(image.scale)) "
            + "orient\(image.imageOrientation.rawValue) \(pixels)"
    }

    static func framing(_ framing: MediaFraming?) -> String {
        guard let framing else { return "none" }
        return "unit(\(fmt(framing.x)),\(fmt(framing.y)) "
            + "\(fmt(framing.width))×\(fmt(framing.height)))"
    }
}
