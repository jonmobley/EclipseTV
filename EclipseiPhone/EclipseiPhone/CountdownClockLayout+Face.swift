//
//  CountdownClockLayout+Face.swift
//  Eclipse
//
//  Places the digits, their plate and the caption on a canvas. The plate is the
//  digit label's own rounded background, and the caption is a small label the
//  digit label hosts above itself, so every surface keeps drawing one label.
//  Thread Safety: Main-actor UIKit drawing.
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Face Drawing

extension CountdownClockLayout {

    /// Fits the digits (with `face`'s plate and caption) into `bounds`.
    /// - Parameters:
    ///   - label: The digit label; it also hosts the caption.
    ///   - text: Clock text, e.g. `4:59`.
    ///   - isExpired: Turns the digits red (a spent clock).
    ///   - face: Caption and plate to draw.
    ///   - bounds: Canvas the layout's unit position is measured in.
    @MainActor
    func apply(
        to label: UILabel,
        text: String,
        isExpired: Bool,
        face: CountdownClockFace,
        in bounds: CGRect
    ) {
        guard bounds.width > 1, bounds.height > 1 else { return }
        let fontSize = fittedFontSize(text: text, face: face, in: bounds)
        let font = Self.digitFont(fontSize)
        let frame = faceFrame(text: text, font: font, face: face, in: bounds)
        label.font = font
        label.text = text
        label.textColor = isExpired ? .systemRed : .white
        label.textAlignment = .center
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = frame.width >= bounds.width - 1
        label.minimumScaleFactor = 0.6
        label.frame = frame
        Self.paintPlate(on: label, face: face, fontSize: fontSize)
        Self.placeCaption(in: label, face: face, fontSize: fontSize)
    }

    /// Digit frame (plate included) for `face`, centered on the layout point and
    /// kept on the canvas together with the caption above it.
    @MainActor
    func faceFrame(
        text: String,
        font: UIFont,
        face: CountdownClockFace,
        in bounds: CGRect
    ) -> CGRect {
        let fitted = (text as NSString).size(withAttributes: [.font: font])
        let pad = face.digitPad(fontSize: font.pointSize)
        let captionHeight = face.captionBlockHeight(fontSize: font.pointSize)
        let width = min(max(ceil(fitted.width) + pad.width * 2, 1), bounds.width)
        let height = min(
            max(ceil(fitted.height) + pad.height * 2, 1),
            max(bounds.height - captionHeight, 1)
        )
        var x = CGFloat(centerX) * bounds.width - width / 2
        var y = CGFloat(centerY) * bounds.height - height / 2
        x = min(max(0, x), bounds.width - width)
        y = min(max(captionHeight, y), bounds.height - height)
        return CGRect(x: x, y: y, width: width, height: height)
    }

    // MARK: - Private

    /// Layout font size, shrunk when a plate and caption would not fit the canvas.
    @MainActor
    private func fittedFontSize(
        text: String,
        face: CountdownClockFace,
        in bounds: CGRect
    ) -> CGFloat {
        let size = fontSize(in: bounds.size)
        guard face != .plain else { return size }
        let fitted = (text as NSString).size(withAttributes: [.font: Self.digitFont(size)])
        let pad = face.digitPad(fontSize: size)
        let blockWidth = fitted.width + pad.width * 2
        let blockHeight = fitted.height + pad.height * 2
            + face.captionBlockHeight(fontSize: size)
        let fit = min(1, bounds.width / blockWidth, bounds.height / blockHeight)
        return max(size * fit, 1)
    }

    private static func digitFont(_ size: CGFloat) -> UIFont {
        UIFont.monospacedDigitSystemFont(ofSize: size, weight: .semibold)
    }

    /// The plate is the label's own layer background, so it moves with the digits.
    @MainActor
    private static func paintPlate(on label: UILabel, face: CountdownClockFace, fontSize: CGFloat) {
        let layer = label.layer
        layer.cornerCurve = .continuous
        if face.showsPlate {
            label.backgroundColor = CountdownClockFace.plateColor
            layer.cornerRadius = fontSize * CountdownClockFace.plateCornerFactor
            layer.borderWidth = max(1, fontSize * CountdownClockFace.plateEdgeFactor)
            layer.borderColor = CountdownClockFace.plateEdgeColor.cgColor
            label.shadowColor = nil
        } else {
            label.backgroundColor = .clear
            layer.cornerRadius = 0
            layer.borderWidth = 0
            // A plate-less clock may sit on a bright picture; a soft shadow keeps it legible.
            label.shadowColor = face == .plain ? nil : UIColor.black.withAlphaComponent(0.55)
            label.shadowOffset = CGSize(width: 0, height: 1)
        }
    }

    /// Positions (or hides) the caption chip just above the digit label.
    @MainActor
    private static func placeCaption(in label: UILabel, face: CountdownClockFace, fontSize: CGFloat) {
        let existing = label.viewWithTag(CountdownClockFace.captionTag) as? UILabel
        guard let text = face.captionText(fontSize: fontSize) else {
            existing?.isHidden = true
            return
        }
        let caption = existing ?? makeCaptionLabel(in: label)
        let size = face.captionSize(fontSize: fontSize)
        caption.attributedText = text
        caption.isHidden = false
        caption.frame = CGRect(
            x: (label.bounds.width - size.width) / 2,
            y: -size.height - fontSize * CountdownClockFace.captionSpacingFactor,
            width: size.width,
            height: size.height
        )
        caption.backgroundColor = face.showsPlate ? CountdownClockFace.plateColor : .clear
        caption.layer.cornerRadius = fontSize * CountdownClockFace.captionCornerFactor
        caption.layer.borderWidth = face.showsPlate
            ? max(1, fontSize * CountdownClockFace.plateEdgeFactor) : 0
        caption.shadowColor = face.showsPlate ? nil : UIColor.black.withAlphaComponent(0.55)
    }

    @MainActor
    private static func makeCaptionLabel(in label: UILabel) -> UILabel {
        let caption = UILabel()
        caption.tag = CountdownClockFace.captionTag
        caption.textAlignment = .center
        caption.numberOfLines = 1
        caption.adjustsFontSizeToFitWidth = true
        caption.minimumScaleFactor = 0.5
        caption.layer.cornerCurve = .continuous
        caption.layer.borderColor = CountdownClockFace.plateEdgeColor.cgColor
        caption.shadowOffset = CGSize(width: 0, height: 1)
        caption.isAccessibilityElement = false
        label.clipsToBounds = false
        label.addSubview(caption)
        return caption
    }
}
