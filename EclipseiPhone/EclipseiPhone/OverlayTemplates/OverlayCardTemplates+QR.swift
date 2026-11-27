//
//  OverlayCardTemplates+QR.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: QR Code card template descriptor — URL plus optional caption,
//               authored with free placement like a timer card.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - QR Template

extension OverlayCardTemplate {

    /// Field keys for the QR Code template.
    enum QRKey {
        static let url = "url"
        static let caption = "caption"
    }

    /// Scannable QR overlay with a link and an optional caption under the code.
    static let qrCode = OverlayCardTemplate(
        kind: .qrCode,
        displayName: "QR Code",
        menuIcon: "qrcode",
        cardIcon: "qrcode",
        category: .connectivity,
        fields: [
            OverlayCardField(
                key: QRKey.url,
                label: "Link",
                placeholder: "https://example.com",
                isSecure: false
            ),
            OverlayCardField(
                key: QRKey.caption,
                label: "Caption",
                placeholder: "Optional caption",
                isSecure: false
            )
        ],
        previewFields: [
            QRKey.url: "https://example.com",
            QRKey.caption: "Scan for more"
        ],
        defaultStyle: qrDefaultStyle,
        title: { fields in
            trimmed(fields, QRKey.caption)
                ?? trimmed(fields, QRKey.url)
                ?? "QR Code"
        },
        subtitle: { fields in
            // Caption already used as title when present; otherwise show nothing
            // under the grid name (the QR itself carries the link).
            trimmed(fields, QRKey.caption) == nil
                ? nil
                : trimmed(fields, QRKey.url)
        }
    )

    /// High-contrast light card so the QR quiet zone stays scannable on air.
    private static var qrDefaultStyle: OverlayCardStyle {
        var style = OverlayCardLook.corporate.style(
            titleSize: OverlayCardTheme.TypeScale.secondary,
            textAlignment: .center
        )
        style.backgroundColor = RGBAColor(red: 1, green: 1, blue: 1)
        return style
    }
}
