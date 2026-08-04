//
//  AudioPlaylist.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A user-created playlist of `AudioTrack` ids.
struct AudioPlaylist: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var name: String
    /// Track ids in play order.
    var trackIds: [UUID]
    let createdAt: Date
    /// Bundled / system playlists that cannot be deleted or renamed.
    var isProtected: Bool

    /// Creates an empty playlist named `name`.
    init(
        id: UUID = UUID(),
        name: String,
        trackIds: [UUID] = [],
        createdAt: Date = Date(),
        isProtected: Bool = false
    ) {
        self.id = id
        self.name = name
        self.trackIds = trackIds
        self.createdAt = createdAt
        self.isProtected = isProtected
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, trackIds, createdAt, isProtected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        trackIds = try c.decode([UUID].self, forKey: .trackIds)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isProtected = try c.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(name, forKey: .name)
        try c.encode(trackIds, forKey: .trackIds)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isProtected, forKey: .isProtected)
    }
}
