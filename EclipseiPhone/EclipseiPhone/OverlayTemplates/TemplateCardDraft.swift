//
//  TemplateCardDraft.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Editable state behind the template field editor: fields,
//               look, position, and announcement auto-remove, turned into an
//               `OverlayCardConfig` the same way the Mac editor does.
//  Thread Safety: Value type - no shared mutable state.
//

import Foundation

// MARK: - TemplateCardPosition

/// Where the editor puts the card: a corner dock, centered, or a placement
/// the Mac set by dragging (kept as is until the operator picks another).
enum TemplateCardPosition: Hashable {
    case corner(OverlayCorner)
    case center
    case custom

    /// User-facing label for the position picker.
    var label: String {
        switch self {
        case .corner(let corner): return corner.label
        case .center: return "Center"
        case .custom: return "Custom"
        }
    }
}

// MARK: - TemplateCardDraft

/// The editor's working copy of a card.
struct TemplateCardDraft: Equatable {

    // MARK: - Constants

    /// Announcement auto-remove defaults (same as the Mac).
    static let defaultAutoRemoveSeconds = 15
    static let autoRemoveRange = 3...300

    // MARK: - Properties

    let template: OverlayCardTemplate.Kind
    var name: String
    var fields: [String: String]
    var corner: OverlayCorner
    var placement: OverlayCardPlacement?
    var style: OverlayCardStyle
    var autoRemoveEnabled: Bool
    var autoRemoveSeconds: Int
    /// Carried through untouched so a Mac AI-made card keeps its flag.
    let madeByAI: Bool?

    // MARK: - Initialization

    /// A fresh draft for `kind` with empty fields and the template's defaults.
    init(newCardOf kind: OverlayCardTemplateKind) {
        let descriptor = OverlayCardTemplate.descriptor(for: kind)
        template = kind
        name = descriptor.displayName
        fields = Dictionary(uniqueKeysWithValues: descriptor.fields.map { ($0.key, "") })
        corner = kind.preferredCorner
        placement = OverlayCardTemplate.defaultPlacement(for: kind)
        style = descriptor.defaultStyle
        autoRemoveEnabled = false
        autoRemoveSeconds = Self.defaultAutoRemoveSeconds
        madeByAI = nil
    }

    /// A draft seeded from an existing card.
    init(editing card: ShowTemplateCard) {
        let config = card.config
        template = config.template
        name = card.name
        fields = config.fields
        corner = config.corner
        placement = config.placement
        style = config.resolvedStyle
        autoRemoveEnabled = config.autoRemoveAfterSeconds != nil
        autoRemoveSeconds = config.autoRemoveAfterSeconds ?? Self.defaultAutoRemoveSeconds
        madeByAI = config.madeByAI
    }

    // MARK: - Derived

    /// The template descriptor (fields, display name).
    var descriptor: OverlayCardTemplate { OverlayCardTemplate.descriptor(for: template) }

    /// Whether this template offers "remove after".
    var supportsAutoRemove: Bool { template == .announcement }

    /// Add / Save is enabled once the first field has text (Mac rule).
    var canCommit: Bool {
        guard let key = descriptor.fields.first?.key else { return true }
        return !(fields[key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// The config to save.
    var config: OverlayCardConfig {
        OverlayCardConfig(
            template: template,
            fields: fields,
            corner: corner,
            style: style,
            placement: placement,
            autoRemoveAfterSeconds: supportsAutoRemove && autoRemoveEnabled
                ? min(Self.autoRemoveRange.upperBound,
                      max(Self.autoRemoveRange.lowerBound, autoRemoveSeconds))
                : nil,
            madeByAI: madeByAI
        )
    }

    /// The look whose palette the style currently matches, if any.
    var look: OverlayCardLook? { OverlayCardLook.matching(style) }

    // MARK: - Position

    /// Positions the picker offers (Custom only while a dragged placement is kept).
    var positionChoices: [TemplateCardPosition] {
        var choices = OverlayCorner.allCases.map { TemplateCardPosition.corner($0) }
        choices.insert(.center, at: 0)
        if position == .custom { choices.append(.custom) }
        return choices
    }

    /// The current position.
    var position: TemplateCardPosition {
        guard let placement else { return .corner(corner) }
        let clamped = placement.clamped()
        return clamped.centerX == 0.5 && clamped.centerY == 0.5 ? .center : .custom
    }

    /// Applies a position choice; corners dock (placement cleared).
    mutating func setPosition(_ choice: TemplateCardPosition) {
        switch choice {
        case .corner(let newCorner):
            corner = newCorner
            placement = nil
        case .center:
            placement = OverlayCardPlacement(centerX: 0.5, centerY: 0.5, scale: placement?.scale ?? 1)
        case .custom:
            break
        }
    }

    /// Applies a shared look, keeping the template's own sizes and layout.
    mutating func applyLook(_ look: OverlayCardLook) {
        style = look.apply(to: style)
    }
}

// MARK: - Kind Alias

extension OverlayCardTemplate {
    /// Shorthand used by the editor.
    typealias Kind = OverlayCardTemplateKind
}
