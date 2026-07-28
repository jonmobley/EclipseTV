//
//  LocalAlbum.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A user-created on-device album that groups media by library item id.
struct LocalAlbum: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Media ids (`LibraryItemDTO.id` / local file names) in display order.
    var itemIds: [String]
    /// Preferred cover media id; falls back to the first item when nil/missing.
    var coverId: String?
    /// Display Mode this album belongs to (home grid + media bucket).
    var orientation: ExternalOutputOrientation
    let createdAt: Date

    /// Creates an empty album with `name` in `orientation`.
    init(
        id: UUID = UUID(),
        name: String,
        itemIds: [String] = [],
        coverId: String? = nil,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.itemIds = itemIds
        self.coverId = coverId
        self.orientation = orientation
        self.createdAt = createdAt
    }

    /// Effective cover id for thumbnail display.
    var resolvedCoverId: String? {
        if let coverId, itemIds.contains(coverId) { return coverId }
        return itemIds.first
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, name, itemIds, coverId, orientation, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        itemIds = try c.decode([String].self, forKey: .itemIds)
        coverId = try c.decodeIfPresent(String.self, forKey: .coverId)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        // Pre-mode albums land in Landscape (app default).
        let raw = try c.decodeIfPresent(String.self, forKey: .orientation)
        orientation = ExternalOutputOrientation.resolved(fromStored: raw)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(itemIds, forKey: .itemIds)
        try c.encodeIfPresent(coverId, forKey: .coverId)
        try c.encode(orientation.rawValue, forKey: .orientation)
        try c.encode(createdAt, forKey: .createdAt)
    }
}
