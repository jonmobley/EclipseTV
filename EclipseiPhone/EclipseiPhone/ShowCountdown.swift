//
//  ShowCountdown.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A named timer tile in a Show. Duration is seconds until 0:00.
struct ShowCountdown: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    /// Show (`LocalAlbum`) this countdown belongs to.
    var showId: UUID
    var name: String
    /// Length in seconds (clamped 1s…24h).
    var duration: Int
    let createdAt: Date

    /// Creates a countdown with `name` and `duration`.
    init(
        id: UUID = UUID(),
        showId: UUID,
        name: String,
        duration: Int,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showId = showId
        self.name = name
        self.duration = duration
        self.createdAt = createdAt
    }

    /// Tile caption: name plus remaining or full length.
    func tileTitle(remaining: Int? = nil) -> String {
        let seconds = remaining ?? duration
        return "\(name)\n\(CountdownController.displayString(seconds: seconds))"
    }
}
