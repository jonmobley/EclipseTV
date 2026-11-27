//
//  OverlayCard.swift
//  Eclipse (iPhone/iPad port of the Mac file of the same name;
//  keep the Codable shapes identical to EclipsePro)
//
//  Description: Models and template registry for template-driven text/card
//               overlays (e.g. a Wi-Fi info card). A card overlay is a layered
//               overlay that carries structured field data instead of an image,
//               anchored to a screen corner. Adding a new template is one enum
//               case plus one descriptor here.
//  Thread Safety: Value types - no shared mutable state.
//

import SwiftUI

// MARK: - OverlayCardTemplateKind

/// Identifies which built-in template a card overlay renders.
///
/// Conforms to `CaseIterable` so the Add menu can list every template, and
/// `Codable` so the chosen template persists with the media item.
enum OverlayCardTemplateKind: String, Codable, CaseIterable, Identifiable {
    case wifi
    case qrCode
    case announcement
    case lowerThird
    case lowerThirdBanner
    case lowerThirdGlass
    case lowerThirdSpeaker
    case lowerThirdTopic
    case titleSubtitle
    case scripture
    case chapterMarker
    case upNext
    case eventTitle
    case nowPlaying
    case agendaItem
    case locationCallout
    case sponsorEndcard
    case socialHandle
    case subscribeCta
    case pollPrompt
    case chatQuestion
    case quizTerm
    case scoreboardVersus
    case scoreboardMatch
    case scoreboardPlayers
    case scoreboardClock
    case scoreboardSeries

    var id: String { rawValue }
}

// MARK: - OverlayCardCategory

/// Grouping used by the template picker's filter bar.
///
/// Conforms to `CaseIterable` so the filter bar can list every category, and
/// `Codable` so it can travel with template metadata if persisted later.
enum OverlayCardCategory: String, Codable, CaseIterable, Identifiable {
    case connectivity
    case event
    case social
    case info
    case lowerThirds
    case sports

    var id: String { rawValue }

    /// User-facing label for the filter chips.
    var label: String {
        switch self {
        case .connectivity: return "Connectivity"
        case .event: return "Event"
        case .social: return "Social"
        case .info: return "Info"
        case .lowerThirds: return "Lower Thirds"
        case .sports: return "Scoring"
        }
    }
}

// MARK: - OverlayCorner

/// The screen corner a card overlay is anchored to.
enum OverlayCorner: String, Codable, CaseIterable, Identifiable {
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    /// User-facing label for the corner picker.
    var label: String {
        switch self {
        case .topLeading: return "Top Left"
        case .topTrailing: return "Top Right"
        case .bottomLeading: return "Bottom Left"
        case .bottomTrailing: return "Bottom Right"
        }
    }

    /// SwiftUI alignment used to pin the card inside its container.
    var alignment: Alignment {
        switch self {
        case .topLeading: return .topLeading
        case .topTrailing: return .topTrailing
        case .bottomLeading: return .bottomLeading
        case .bottomTrailing: return .bottomTrailing
        }
    }
}

// MARK: - OverlayCardConfig

/// Persisted configuration for a template-driven card overlay.
///
/// Stores the chosen template, the user-entered field values keyed by the
/// template's field keys, and the corner the card is anchored to. The resolved
/// title/subtitle/icon are derived on demand from the template descriptor so
/// the visual stays in sync with the template definition.
struct OverlayCardConfig: Codable, Equatable {

    // MARK: - Stored Properties

    var template: OverlayCardTemplateKind
    var fields: [String: String]
    var corner: OverlayCorner
    /// Operator-chosen appearance. Optional so cards saved before styling
    /// existed still decode; `resolvedStyle` supplies the fallback.
    var style: OverlayCardStyle?
    /// Free-placement geometry. When nil the card docks to `corner`; once the
    /// operator drags/resizes it on the preview this holds the exact position.
    var placement: OverlayCardPlacement?
    /// Seconds after going live before the card auto-dismisses. Announcement
    /// templates only; `nil` means stay live until manually removed. Optional
    /// so cards saved before auto-remove existed still decode.
    var autoRemoveAfterSeconds: Int?
    /// True when the Create page's AI wrote the card. Optional so older
    /// saves decode; nil means made by hand. Shown as a sparkles badge.
    var madeByAI: Bool?

    // MARK: - Initialization

    init(template: OverlayCardTemplateKind,
         fields: [String: String],
         corner: OverlayCorner = .topTrailing,
         style: OverlayCardStyle? = nil,
         placement: OverlayCardPlacement? = nil,
         autoRemoveAfterSeconds: Int? = nil,
         madeByAI: Bool? = nil) {
        self.template = template
        self.fields = fields
        self.corner = corner
        self.style = style
        self.placement = placement
        self.autoRemoveAfterSeconds = autoRemoveAfterSeconds
        self.madeByAI = madeByAI
    }

    // MARK: - Derived Display Values

    /// The template descriptor backing this config.
    var descriptor: OverlayCardTemplate {
        OverlayCardTemplate.descriptor(for: template)
    }

    /// The effective style, falling back to the shared default when a card was
    /// created (or saved) without an explicit style.
    var resolvedStyle: OverlayCardStyle {
        style ?? OverlayCardTemplate.descriptor(for: template).defaultStyle
    }

    /// SF Symbol shown on the left of the card.
    var cardIcon: String { descriptor.cardIcon }

    /// Bold primary line, derived from the entered fields.
    var resolvedTitle: String { descriptor.title(fields) }

    /// Optional secondary line, derived from the entered fields.
    var resolvedSubtitle: String? { descriptor.subtitle(fields) }

    /// Copy with secure field values replaced by bullets (e.g. Wi-Fi password).
    ///
    /// Used for LAN remote thumbnails so paired phones never receive venue
    /// credentials in `/thumb/` PNGs while the live program still shows them.
    func maskingSecureFields(mask: String = "••••••••") -> OverlayCardConfig {
        var masked = fields
        for field in descriptor.fields where field.isSecure {
            guard let value = masked[field.key], !value.isEmpty else { continue }
            masked[field.key] = mask
        }
        return OverlayCardConfig(
            template: template,
            fields: masked,
            corner: corner,
            style: style,
            placement: placement,
            autoRemoveAfterSeconds: autoRemoveAfterSeconds,
            madeByAI: madeByAI
        )
    }
}

// MARK: - OverlayCardField

/// One editable field in a card template.
struct OverlayCardField: Identifiable {
    let key: String
    let label: String
    let placeholder: String
    let isSecure: Bool

    var id: String { key }
}

// MARK: - OverlayCardTemplate

/// Static description of a card template: its icons, editable fields, and how
/// to derive the displayed title/subtitle from entered field values.
///
/// To add a template: add a `OverlayCardTemplateKind` case, then append a
/// descriptor in `all`. No render or persistence plumbing changes are needed.
struct OverlayCardTemplate: Identifiable {

    // MARK: - Properties

    var id: OverlayCardTemplateKind { kind }

    let kind: OverlayCardTemplateKind
    let displayName: String
    /// SF Symbol used in the Add menu.
    let menuIcon: String
    /// SF Symbol shown on the rendered card.
    let cardIcon: String
    /// Grouping used by the template picker's filter bar.
    let category: OverlayCardCategory
    let fields: [OverlayCardField]
    /// Sample field values used to render the picker's preview tile.
    let previewFields: [String: String]
    /// Appearance applied when the operator first creates this template.
    let defaultStyle: OverlayCardStyle
    /// Derives the bold primary line from entered field values.
    let title: ([String: String]) -> String
    /// Derives the optional secondary line from entered field values.
    let subtitle: ([String: String]) -> String?

    /// A ready-to-render configuration for the picker's preview tile.
    var sampleConfig: OverlayCardConfig {
        OverlayCardConfig(
            template: kind,
            fields: previewFields,
            corner: kind.preferredCorner,
            style: defaultStyle,
            placement: OverlayCardTemplate.defaultPlacement(for: kind)
        )
    }

    // MARK: - Registry

    /// Every available template, in Add-menu order. Descriptors live in the
    /// `OverlayCardTemplates+*` extension files, grouped by category.
    static let all: [OverlayCardTemplate] = [
        wifi, qrCode, announcement,
        lowerThird, lowerThirdBanner, lowerThirdGlass, lowerThirdSpeaker,
        lowerThirdTopic,
        titleSubtitle, scripture, chapterMarker, quizTerm,
        upNext, eventTitle, nowPlaying, agendaItem, locationCallout,
        sponsorEndcard,
        socialHandle, subscribeCta, pollPrompt, chatQuestion,
        scoreboardVersus, scoreboardMatch, scoreboardPlayers,
        scoreboardClock, scoreboardSeries
    ]

    /// Free placement used for centered cards (QR, sponsor end-card).
    static func defaultPlacement(
        for kind: OverlayCardTemplateKind
    ) -> OverlayCardPlacement? {
        switch kind {
        case .qrCode, .sponsorEndcard:
            return qrDefaultPlacement
        default:
            return nil
        }
    }

    /// Centered free placement used when authoring a QR code card.
    static let qrDefaultPlacement = OverlayCardPlacement(
        centerX: 0.5, centerY: 0.5, scale: 1
    )

    /// Returns the descriptor for a template kind.
    static func descriptor(for kind: OverlayCardTemplateKind) -> OverlayCardTemplate {
        all.first { $0.kind == kind } ?? wifi
    }
}

// MARK: - Field Helpers

extension OverlayCardTemplate {

    /// Returns the trimmed value for `key`, or nil when empty/missing. Used by
    /// template `title`/`subtitle` closures to derive display lines.
    static func trimmed(_ fields: [String: String], _ key: String) -> String? {
        let value = fields[key]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (value?.isEmpty == false) ? value : nil
    }
}
