//
//  OverlayCardTemplates+LowerThird.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Broadcast lower-third card templates (Accent Bar, Nameplate,
//               Glass Strip). Descriptors only; layout lives in
//               OverlayCardLowerThirdContent.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - Lower Third Templates

extension OverlayCardTemplate {

    /// Shared field keys for lower-third templates.
    enum LowerThirdKey {
        static let name = "name"
        static let role = "role"
        static let org = "org"
    }

    // MARK: - Accent Bar

    /// Classic lower third: vertical accent bar with name and role.
    static let lowerThird = OverlayCardTemplate(
        kind: .lowerThird,
        displayName: "Accent Bar",
        menuIcon: "person.text.rectangle",
        cardIcon: "person.fill",
        category: .lowerThirds,
        fields: lowerThirdFields,
        previewFields: lowerThirdPreviewFields,
        defaultStyle: accentBarDefaultStyle,
        title: { fields in trimmed(fields, LowerThirdKey.name) ?? "Name" },
        subtitle: { fields in trimmed(fields, LowerThirdKey.role) }
    )

    // MARK: - Nameplate

    /// Two-band nameplate: name on a solid plate, role on an accent strip.
    static let lowerThirdBanner = OverlayCardTemplate(
        kind: .lowerThirdBanner,
        displayName: "Nameplate",
        menuIcon: "rectangle.bottomhalf.filled",
        cardIcon: "rectangle.bottomhalf.filled",
        category: .lowerThirds,
        fields: lowerThirdFields,
        previewFields: [
            LowerThirdKey.name: "Jordan Lee",
            LowerThirdKey.role: "Executive Producer"
        ],
        defaultStyle: nameplateDefaultStyle,
        title: { fields in trimmed(fields, LowerThirdKey.name) ?? "Name" },
        subtitle: { fields in trimmed(fields, LowerThirdKey.role) }
    )

    // MARK: - Glass Strip

    /// Soft translucent strip with an underline accent under the name.
    static let lowerThirdGlass = OverlayCardTemplate(
        kind: .lowerThirdGlass,
        displayName: "Glass Strip",
        menuIcon: "rectangle.portrait.on.rectangle.portrait",
        cardIcon: "rectangle.portrait.on.rectangle.portrait",
        category: .lowerThirds,
        fields: lowerThirdFields,
        previewFields: [
            LowerThirdKey.name: "Sam Ortiz",
            LowerThirdKey.role: "Correspondent"
        ],
        defaultStyle: glassStripDefaultStyle,
        title: { fields in trimmed(fields, LowerThirdKey.name) ?? "Name" },
        subtitle: { fields in trimmed(fields, LowerThirdKey.role) }
    )

    // MARK: - Speaker

    /// Three-line speaker bug: name, role, and organization.
    static let lowerThirdSpeaker = OverlayCardTemplate(
        kind: .lowerThirdSpeaker,
        displayName: "Speaker",
        menuIcon: "person.crop.rectangle",
        cardIcon: "person.fill",
        category: .lowerThirds,
        fields: speakerFields,
        previewFields: [
            LowerThirdKey.name: "Dr. Morgan Hale",
            LowerThirdKey.role: "Keynote Speaker",
            LowerThirdKey.org: "Northwind University"
        ],
        defaultStyle: accentBarDefaultStyle,
        title: { fields in trimmed(fields, LowerThirdKey.name) ?? "Name" },
        subtitle: { fields in speakerSubtitle(fields) }
    )

    // MARK: - Shared Fields

    private static var lowerThirdFields: [OverlayCardField] {
        [
            OverlayCardField(
                key: LowerThirdKey.name,
                label: "Name",
                placeholder: "Full name",
                isSecure: false
            ),
            OverlayCardField(
                key: LowerThirdKey.role,
                label: "Role / Title",
                placeholder: "Role or title",
                isSecure: false
            )
        ]
    }

    private static var speakerFields: [OverlayCardField] {
        lowerThirdFields + [
            OverlayCardField(
                key: LowerThirdKey.org,
                label: "Organization",
                placeholder: "Company or org",
                isSecure: false
            )
        ]
    }

    private static func speakerSubtitle(_ fields: [String: String]) -> String? {
        let role = trimmed(fields, LowerThirdKey.role)
        let org = trimmed(fields, LowerThirdKey.org)
        switch (role, org) {
        case let (role?, org?): return "\(role) · \(org)"
        case let (role?, nil): return role
        case let (nil, org?): return org
        case (nil, nil): return nil
        }
    }

    // MARK: - Topic Bar

    /// Field keys for the Topic Bar template.
    enum TopicBarKey {
        static let topic = "topic"
        static let context = "context"
    }

    /// Thin single-topic ticker strip for segment titles and talking points.
    static let lowerThirdTopic = OverlayCardTemplate(
        kind: .lowerThirdTopic,
        displayName: "Topic Bar",
        menuIcon: "text.badge.checkmark",
        cardIcon: "text.alignleft",
        category: .lowerThirds,
        fields: [
            OverlayCardField(
                key: TopicBarKey.topic,
                label: "Topic",
                placeholder: "Topic or talking point",
                isSecure: false
            ),
            OverlayCardField(
                key: TopicBarKey.context,
                label: "Context",
                placeholder: "Optional context",
                isSecure: false
            )
        ],
        previewFields: [
            TopicBarKey.topic: "Budget Outlook",
            TopicBarKey.context: "Q3 Planning"
        ],
        defaultStyle: OverlayCardLook.standard.style(),
        title: { fields in trimmed(fields, TopicBarKey.topic) ?? "Topic" },
        subtitle: { fields in trimmed(fields, TopicBarKey.context) }
    )

    private static var lowerThirdPreviewFields: [String: String] {
        [
            LowerThirdKey.name: "Alex Rivera",
            LowerThirdKey.role: "Guest Speaker"
        ]
    }

    // MARK: - Default Styles

    private static var accentBarDefaultStyle: OverlayCardStyle {
        OverlayCardLook.standard.style()
    }

    private static var nameplateDefaultStyle: OverlayCardStyle {
        OverlayCardLook.standard.style()
    }

    private static var glassStripDefaultStyle: OverlayCardStyle {
        var style = OverlayCardLook.standard.style()
        style.backgroundOpacity = OverlayCardTheme.opacityGlass
        return style
    }
}
