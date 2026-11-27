//
//  OverlayCardQRContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Visual for the QR Code card template: scannable code plus an
//               optional caption on the shared plate (white by default so
//               phones can read it; no spine, the card is symmetrical).
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardQRContent

/// QR Code card: the code at a fixed, scannable size, caption underneath.
struct OverlayCardQRContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    // MARK: - Constants

    private enum Metric {
        /// Side of the code at the 1080p reference; large enough to scan
        /// from a seat in a mid-size room.
        static let codeSide: CGFloat = 280
        static let placeholderRadius: CGFloat = 8
    }

    private typealias Space = OverlayCardTheme.Space

    private var style: OverlayCardStyle { config.resolvedStyle }

    private var payload: String {
        OverlayCardTemplate.trimmed(config.fields, OverlayCardTemplate.QRKey.url) ?? ""
    }

    private var caption: String? {
        OverlayCardTemplate.trimmed(config.fields, OverlayCardTemplate.QRKey.caption)
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: Space.stackGap * scale) {
            qrImage
            if let caption {
                Text(caption)
                    .font(.system(
                        size: style.titleSize * scale,
                        weight: style.titleWeight.weight,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(style.textColor.color)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
        }
        .padding(Space.padV * scale)
        .cardPlate(style: style, scale: scale, showsSpine: false)
        .fixedSize()
    }

    // MARK: - Subviews

    @ViewBuilder
    private var qrImage: some View {
        let side = Metric.codeSide * scale
        if let image = OverlayQRCodeImage.make(from: payload, side: max(side, 1)) {
            Image(uiImage: image)
                .interpolation(.none)
                .resizable()
                .frame(width: side, height: side)
        } else {
            placeholder(side: side)
        }
    }

    private func placeholder(side: CGFloat) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: Metric.placeholderRadius * scale, style: .continuous)
                .fill(Color.black.opacity(0.06))
            Image(systemName: "qrcode")
                .font(.system(size: side * 0.35, weight: .semibold))
                .foregroundStyle(Color.black.opacity(0.25))
        }
        .frame(width: side, height: side)
    }
}
