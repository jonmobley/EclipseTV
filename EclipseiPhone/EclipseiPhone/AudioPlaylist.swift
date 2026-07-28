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

    /// Creates an empty playlist named `name`.
    init(
        id: UUID = UUID(),
        name: String,
        trackIds: [UUID] = [],
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.trackIds = trackIds
        self.createdAt = createdAt
    }
}
