//
//  OverlayCardLowerThirdContent.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Lower-third layouts for Accent Bar, Speaker, Nameplate,
//               Glass Strip, and Topic Bar card templates, all on the shared
//               card plate.
//  Thread Safety: Main thread only - SwiftUI view component.
//

import SwiftUI

// MARK: - OverlayCardLowerThirdContent

/// Lower-third card family.
///
/// Accent Bar and Speaker stack name / role / organisation. Nameplate adds an
/// accent band carrying the role. Glass Strip is the one see-through plate.
/// Topic Bar leads with a context eyebrow over the topic.
struct OverlayCardLowerThirdContent: View {

    // MARK: - Properties

    let config: OverlayCardConfig

    /// Multiplier applied to every metric (1.0 == 1080p reference).
    var scale: CGFloat = 1.0

    // MARK: - Constants

    private enum Metric {
        /// Vertical padding of the Nameplate's accent band.
        static let bandPaddingV: CGFloat = 10
    }

    private var style: OverlayCardStyle { config.resolvedStyle }
    private typealias Key = OverlayCardTemplate.LowerThirdKey
    private typealias Space = OverlayCardTheme.Space

    // MARK: - Body

    var body: some View {
        Group {
            switch config.template {
            case .lowerThird:
                accentBar(showsOrg: false)
            case .lowerThirdSpeaker:
                accentBar(showsOrg: true)
            case .lowerThirdBanner:
                nameplate
            case .lowerThirdGlass:
                glassStrip
            case .lowerThirdTopic:
                topicBar
            default:
                EmptyView()
            }
        }
        .fixedSize()
    }

    // MARK: - Accent Bar / Speaker

    private func accentBar(showsOrg: Bool) -> some View {
        textStack(showsRole: true, showsOrg: showsOrg)
            .modifier(PlatePadding(scale: scale))
            .frame(minWidth: Space.minPlateWidth * scale, alignment: .leading)
            .cardPlate(style: style, scale: scale)
    }

    // MARK: - Nameplate

    /// Name on the plate, role on an accent band below it. The band's text
    /// takes the plate colour so it reads on the accent.
    private var nameplate: some View {
        VStack(alignment: .leading, spacing: 0) {
            textStack(showsRole: false, showsOrg: false)
                .modifier(PlatePadding(scale: scale))
                .frame(maxWidth: .infinity, alignment: .leading)
            if let role = roleText {
                Text(role.uppercased())
                    .font(.system(
                        size: OverlayCardTheme.TypeScale.label(for: style) * scale,
                        weight: .bold,
                        design: style.fontDesign.design
                    ))
                    .tracking(OverlayCardTheme.TypeScale.labelTracking * scale)
                    .foregroundColor(style.backgroundColor.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.leading, (Space.padH + Space.spine) * scale)
                    .padding(.trailing, Space.padH * scale)
                    .padding(.vertical, Metric.bandPaddingV * scale)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accentColor)
            }
        }
        .frame(minWidth: Space.minPlateWidth * scale, alignment: .leading)
        .cardPlate(style: style, scale: scale)
    }

    // MARK: - Glass Strip

    /// Same stack as the Accent Bar; the template's default style lowers the
    /// plate opacity so the picture shows through.
    private var glassStrip: some View {
        accentBar(showsOrg: false)
    }

    // MARK: - Topic Bar

    private var topicBar: some View {
        let topic = OverlayCardTemplate.trimmed(
            config.fields, OverlayCardTemplate.TopicBarKey.topic
        ) ?? "Topic"
        let context = OverlayCardTemplate.trimmed(
            config.fields, OverlayCardTemplate.TopicBarKey.context
        )
        return VStack(alignment: .leading, spacing: Space.lineGap * scale) {
            if let context {
                OverlayCardEyebrow(text: context, style: style, scale: scale)
                    .padding(.bottom, (Space.stackGap - Space.lineGap) * scale)
            }
            Text(topic)
                .font(.system(
                    size: style.titleSize * scale,
                    weight: style.titleWeight.weight,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .modifier(PlatePadding(scale: scale))
        .frame(minWidth: Space.minPlateWidth * scale, alignment: .leading)
        .cardPlate(style: style, scale: scale)
    }

    // MARK: - Shared Pieces

    private var nameText: String {
        OverlayCardTemplate.trimmed(config.fields, Key.name) ?? "Name"
    }

    private var roleText: String? {
        OverlayCardTemplate.trimmed(config.fields, Key.role)
    }

    private var orgText: String? {
        OverlayCardTemplate.trimmed(config.fields, Key.org)
    }

    private var accentColor: Color { style.resolvedAccent.color }

    /// Name, then role and organisation at secondary and label size.
    @ViewBuilder
    private func textStack(showsRole: Bool, showsOrg: Bool) -> some View {
        VStack(alignment: .leading, spacing: Space.lineGap * scale) {
            Text(nameText)
                .font(.system(
                    size: style.titleSize * scale,
                    weight: style.titleWeight.weight,
                    design: style.fontDesign.design
                ))
                .foregroundColor(style.textColor.color)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if showsRole, let role = roleText {
                Text(role)
                    .font(.system(
                        size: style.subtitleSize * scale,
                        weight: .regular,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(style.subtitleColor.color)
                    .lineLimit(2)
                    .minimumScaleFactor(0.75)
            }
            if showsOrg, let org = orgText {
                Text(org)
                    .font(.system(
                        size: OverlayCardTheme.TypeScale.label(for: style) * scale,
                        weight: .medium,
                        design: style.fontDesign.design
                    ))
                    .foregroundColor(style.subtitleColor.color.opacity(0.8))
                    .padding(.top, 2 * scale)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
        }
    }
}

// MARK: - PlatePadding

/// The standard inset of content on the plate: room for the spine on the
/// leading edge, then the shared horizontal and vertical padding.
struct PlatePadding: ViewModifier {

    let scale: CGFloat

    private typealias Space = OverlayCardTheme.Space

    func body(content: Content) -> some View {
        content
            .padding(.leading, (Space.padH + Space.spine) * scale)
            .padding(.trailing, Space.padH * scale)
            .padding(.vertical, Space.padV * scale)
    }
}
