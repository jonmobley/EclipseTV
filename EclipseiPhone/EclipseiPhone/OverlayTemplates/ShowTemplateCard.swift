//
//  ShowTemplateCard.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: A template card ("card overlay" on the Mac) that lives in a
//               Show, plus the surface token that places it on the Show grid.
//  Thread Safety: Value types - no shared mutable state.
//

import Foundation

// MARK: - ShowTemplateCard

/// One template tile in a Show: a Wi-Fi card, lower third, scoreboard, and so on.
///
/// Tapping the tile lays the card over whatever is live (it never replaces the
/// live picture). `config` is the Mac's `OverlayCardConfig`, byte-compatible so
/// the same card syncs both ways through the `TemplateCard` iCloud record.
struct ShowTemplateCard: Codable, Equatable, Identifiable {

    // MARK: - Properties

    let id: UUID
    /// Show (`LocalAlbum`) this card belongs to.
    var showId: UUID
    /// Tile title; defaults to the template's display name.
    var name: String
    /// Template, field values, corner, style, and placement (Mac shape).
    var config: OverlayCardConfig
    /// Draw order among live overlays; higher draws on top.
    var stackOrder: Int
    let createdAt: Date
    var modifiedAt: Date

    // MARK: - Initialization

    /// Creates a card; `name` falls back to the template's display name.
    init(
        id: UUID = UUID(),
        showId: UUID,
        name: String? = nil,
        config: OverlayCardConfig,
        stackOrder: Int = 0,
        createdAt: Date = Date(),
        modifiedAt: Date? = nil
    ) {
        self.id = id
        self.showId = showId
        self.name = name ?? config.descriptor.displayName
        self.config = config
        self.stackOrder = stackOrder
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
    }

    // MARK: - Derived

    /// The template this card renders.
    var template: OverlayCardTemplateKind { config.template }
}

// MARK: - ShowTemplateToken

/// Reserved surface ids for template tiles in `LocalAlbum.surfaceIds`.
///
/// Same token the Mac writes (`__eclipse.template.<UUID>`), so a Show's grid
/// order round-trips between the two apps.
enum ShowTemplateToken {

    /// Prefix shared by every template surface id.
    static let prefix = "__eclipse.template."

    /// Surface id for the template card with `id`.
    static func token(for id: UUID) -> String {
        prefix + id.uuidString
    }

    /// Whether `id` is a template surface token.
    static func isTemplate(_ id: String) -> Bool {
        id.hasPrefix(prefix)
    }

    /// Card UUID encoded in `token`, if it is a valid template surface id.
    static func templateId(from token: String) -> UUID? {
        guard isTemplate(token) else { return nil }
        return UUID(uuidString: String(token.dropFirst(prefix.count)))
    }
}

// MARK: - Config Coding

extension OverlayCardConfig {

    /// JSON exactly as the Mac writes it for the `TemplateCard.config` field:
    /// a plain `JSONEncoder` with `.sortedKeys` and default strategies.
    func syncJSONString() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Decodes a `TemplateCard.config` string; nil for a missing or bad value,
    /// including a template kind this build does not know.
    static func fromSyncJSON(_ string: String?) -> OverlayCardConfig? {
        guard let data = string?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(OverlayCardConfig.self, from: data)
    }
}
