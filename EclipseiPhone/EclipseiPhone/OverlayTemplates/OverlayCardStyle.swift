//
//  OverlayCardStyle.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Codable styling model for template-driven card overlays. Carries
//               the fully operator-configurable look (font design, weight, sizes,
//               text/background colors, alignment, corner radius, icon toggle) so
//               a single style drives the preview, external display, cast, virtual
//               camera, recording, and thumbnails identically.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI
import UIKit

// MARK: - OverlayCardFontDesign

/// Font family family used across a card's title and subtitle.
enum OverlayCardFontDesign: String, Codable, CaseIterable, Identifiable {
    case system
    case rounded
    case serif
    case monospaced

    var id: String { rawValue }

    /// User-facing label for the design picker.
    var label: String {
        switch self {
        case .system: return "System"
        case .rounded: return "Rounded"
        case .serif: return "Serif"
        case .monospaced: return "Mono"
        }
    }

    /// The SwiftUI font design this case maps to.
    var design: Font.Design {
        switch self {
        case .system: return .default
        case .rounded: return .rounded
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

// MARK: - OverlayCardFontWeight

/// Codable subset of `Font.Weight` exposed to the operator.
enum OverlayCardFontWeight: String, Codable, CaseIterable, Identifiable {
    case regular
    case medium
    case semibold
    case bold
    case heavy

    var id: String { rawValue }

    /// User-facing label for the weight menu.
    var label: String { rawValue.capitalized }

    /// The SwiftUI font weight this case maps to.
    var weight: Font.Weight {
        switch self {
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        }
    }
}

// MARK: - OverlayCardTextAlignment

/// Horizontal alignment of the card's text stack.
enum OverlayCardTextAlignment: String, Codable, CaseIterable, Identifiable {
    case leading
    case center
    case trailing

    var id: String { rawValue }

    /// User-facing label for the alignment picker.
    var label: String {
        switch self {
        case .leading: return "Left"
        case .center: return "Center"
        case .trailing: return "Right"
        }
    }

    /// Alignment used by the text `VStack`.
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }

    /// Alignment applied to multi-line text runs.
    var multiline: TextAlignment {
        switch self {
        case .leading: return .leading
        case .center: return .center
        case .trailing: return .trailing
        }
    }
}

// MARK: - RGBAColor

/// Codable sRGB color wrapper, since `SwiftUI.Color` is not `Codable`.
struct RGBAColor: Codable, Equatable {

    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Captures the sRGB components of a SwiftUI `Color`, falling back to opaque
    /// white if the color cannot be resolved into the sRGB space.
    init(_ color: Color) {
        var red: CGFloat = 1, green: CGFloat = 1, blue: CGFloat = 1, alpha: CGFloat = 1
        if !UIColor(color).getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
            (red, green, blue, alpha) = (1, 1, 1, 1)
        }
        self.red = Double(red)
        self.green = Double(green)
        self.blue = Double(blue)
        self.alpha = Double(alpha)
    }

    /// The SwiftUI color represented by these components.
    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}

// MARK: - OverlayCardStyle

/// Fully operator-configurable appearance for a card overlay.
///
/// All sizes are expressed at the 1080p reference scale used by `OverlayCardView`
/// so a single value renders proportionally across every output.
struct OverlayCardStyle: Codable, Equatable {

    // MARK: - Stored Properties

    var fontDesign: OverlayCardFontDesign
    var titleWeight: OverlayCardFontWeight
    var titleSize: CGFloat
    var subtitleSize: CGFloat
    var textColor: RGBAColor
    var subtitleColor: RGBAColor
    var backgroundColor: RGBAColor
    var backgroundOpacity: Double
    var cornerRadius: CGFloat
    var textAlignment: OverlayCardTextAlignment
    var showsIcon: Bool
    /// Accent for the spine, eyebrows, badges, and icons. Optional so cards
    /// saved before looks existed still decode; `resolvedAccent` supplies the
    /// shared fallback.
    var accentColor: RGBAColor?

    // MARK: - Derived

    /// The accent to draw with: the stored one, or the shared broadcast accent.
    var resolvedAccent: RGBAColor { accentColor ?? OverlayCardLook.standard.accent }

    /// Whether the plate is light enough to need dark text and a dark hairline.
    var isLightPlate: Bool {
        let c = backgroundColor
        return (0.2126 * c.red + 0.7152 * c.green + 0.0722 * c.blue) > 0.6
    }

    // MARK: - Presets

    /// Named looks offered in the style controls, in display order. Each one
    /// re-skins the current style with `OverlayCardLook.apply(to:)` so the
    /// template keeps its own sizes.
    static let presets: [(name: String, look: OverlayCardLook)] =
        OverlayCardLook.allCases.map { ($0.label, $0) }
}
