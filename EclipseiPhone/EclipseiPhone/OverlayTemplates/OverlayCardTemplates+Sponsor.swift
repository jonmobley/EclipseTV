//
//  OverlayCardTemplates+Sponsor.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Presented By / sponsor end-card template. Descriptor only;
//               layout lives in OverlayCardSponsorContent.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Sponsor Template

extension OverlayCardTemplate {

    /// Field keys for the Presented By template.
    enum SponsorKey {
        static let name = "name"
        static let tagline = "tagline"
    }

    /// Centered end-card for sponsor credit ("Presented by").
    static let sponsorEndcard = OverlayCardTemplate(
        kind: .sponsorEndcard,
        displayName: "Presented By",
        menuIcon: "sparkles.rectangle.stack",
        cardIcon: "sparkles",
        category: .event,
        fields: [
            OverlayCardField(
                key: SponsorKey.name,
                label: "Sponsor",
                placeholder: "Sponsor name",
                isSecure: false
            ),
            OverlayCardField(
                key: SponsorKey.tagline,
                label: "Tagline",
                placeholder: "Optional tagline",
                isSecure: false
            )
        ],
        previewFields: [
            SponsorKey.name: "Northwind Partners",
            SponsorKey.tagline: "Building what's next"
        ],
        defaultStyle: sponsorDefaultStyle,
        title: { fields in trimmed(fields, SponsorKey.name) ?? "Sponsor" },
        subtitle: { fields in trimmed(fields, SponsorKey.tagline) }
    )

    private static var sponsorDefaultStyle: OverlayCardStyle {
        OverlayCardLook.standard.style(textAlignment: .center)
    }
}
