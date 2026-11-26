//
//  OverlayCardLook.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Named looks (Broadcast, Worship, Corporate, Playful) for card
//               overlays. A look is a palette, a typeface, a weight, and a
//               corner radius; it never touches a template's type sizes,
//               alignment, or icon choice, so one look makes every template in
//               a show read as one family.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - OverlayCardLook

/// One of the shared card looks offered in the style controls.
///
/// Applying a look with ``apply(to:)`` keeps the template's own sizes and
/// layout flags, so a scoreboard stays a scoreboard and a lower third keeps
/// its name size; only colors, font family, title weight, plate opacity, and
/// corner radius change.
enum OverlayCardLook: String, Codable, CaseIterable, Identifiable {
    case broadcast
    case worship
    case corporate
    case playful

    var id: String { rawValue }

    /// The look every template starts from.
    static let standard: OverlayCardLook = .broadcast

    /// User-facing name shown on the look buttons.
    var label: String {
        switch self {
        case .broadcast: return "Broadcast"
        case .worship: return "Worship"
        case .corporate: return "Corporate"
        case .playful: return "Playful"
        }
    }

    /// One-line description for hover help and the proposal page.
    var summary: String {
        switch self {
        case .broadcast: return "Solid near-black plate, amber spine, heavy sans. The default."
        case .worship: return "Solid warm charcoal, ivory serif, gold spine. Services and scripture."
        case .corporate: return "Solid white plate, ink text, deep teal spine. Conferences and town halls."
        case .playful: return "Solid deep violet, coral spine, rounded type. Streams, youth, schools."
        }
    }

    // MARK: - Palette

    /// Plate fill color.
    var plate: RGBAColor {
        switch self {
        case .broadcast: return RGBAColor(red: 0.04, green: 0.04, blue: 0.05)
        case .worship: return RGBAColor(red: 0.11, green: 0.09, blue: 0.08)
        case .corporate: return RGBAColor(red: 0.98, green: 0.98, blue: 0.98)
        case .playful: return RGBAColor(red: 0.14, green: 0.10, blue: 0.23)
        }
    }

    /// Plate opacity. Every look runs solid so text keeps full contrast over
    /// any picture; only the Glass Strip template lowers this on its own.
    var plateOpacity: Double { 1 }

    /// Primary text color.
    var text: RGBAColor {
        switch self {
        case .broadcast, .playful: return RGBAColor(red: 1, green: 1, blue: 1)
        case .worship: return RGBAColor(red: 0.97, green: 0.94, blue: 0.88)
        case .corporate: return RGBAColor(red: 0.07, green: 0.09, blue: 0.13)
        }
    }

    /// Secondary text color (roles, details, options).
    var secondary: RGBAColor {
        var color = text
        color.alpha = isLight ? 0.68 : 0.78
        return color
    }

    /// Accent used for the spine, eyebrows, badges, and icons.
    var accent: RGBAColor {
        switch self {
        case .broadcast: return RGBAColor(red: 1.0, green: 0.69, blue: 0.13)
        case .worship: return RGBAColor(red: 0.79, green: 0.64, blue: 0.29)
        case .corporate: return RGBAColor(red: 0.03, green: 0.47, blue: 0.53)
        case .playful: return RGBAColor(red: 1.0, green: 0.36, blue: 0.54)
        }
    }

    /// Whether the plate is light (dark text on it).
    var isLight: Bool { self == .corporate }

    // MARK: - Type & Shape

    /// Font family for every line on the card.
    var fontDesign: OverlayCardFontDesign {
        switch self {
        case .broadcast, .corporate: return .system
        case .worship: return .serif
        case .playful: return .rounded
        }
    }

    /// Weight of the big line.
    var titleWeight: OverlayCardFontWeight {
        switch self {
        case .broadcast, .playful: return .heavy
        case .worship: return .semibold
        case .corporate: return .bold
        }
    }

    /// Plate corner radius at the 1080p reference scale.
    var cornerRadius: CGFloat {
        switch self {
        case .broadcast: return 6
        case .worship: return 18
        case .corporate: return 10
        case .playful: return 28
        }
    }

    // MARK: - Styles

    /// A complete style for a template default: this look plus the template's
    /// own sizes, alignment, and icon choice.
    func style(
        titleSize: CGFloat = OverlayCardTheme.TypeScale.title,
        subtitleSize: CGFloat = OverlayCardTheme.TypeScale.secondary,
        textAlignment: OverlayCardTextAlignment = .leading,
        showsIcon: Bool = false
    ) -> OverlayCardStyle {
        OverlayCardStyle(
            fontDesign: fontDesign,
            titleWeight: titleWeight,
            titleSize: titleSize,
            subtitleSize: subtitleSize,
            textColor: text,
            subtitleColor: secondary,
            backgroundColor: plate,
            backgroundOpacity: plateOpacity,
            cornerRadius: cornerRadius,
            textAlignment: textAlignment,
            showsIcon: showsIcon,
            accentColor: accent
        )
    }

    /// Re-skins an existing style with this look, keeping the template's sizes,
    /// alignment, and icon toggle.
    func apply(to style: OverlayCardStyle) -> OverlayCardStyle {
        var updated = style
        updated.fontDesign = fontDesign
        updated.titleWeight = titleWeight
        updated.textColor = text
        updated.subtitleColor = secondary
        updated.backgroundColor = plate
        updated.backgroundOpacity = plateOpacity
        updated.cornerRadius = cornerRadius
        updated.accentColor = accent
        return updated
    }

    /// The look whose palette a style currently carries, if any. Used to
    /// highlight the active look button.
    static func matching(_ style: OverlayCardStyle) -> OverlayCardLook? {
        allCases.first { look in
            look.plate == style.backgroundColor && look.accent == style.accentColor
        }
    }
}
