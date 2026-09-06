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
    /// Clock size and position on AirPlay / HDMI / Practice.
    var layout: CountdownClockLayout
    /// What renders behind the clock. `.none` is solid black.
    var background: CountdownBackground
    /// What output does at 0:00.
    var endAction: CountdownEndAction
    let createdAt: Date

    /// Creates a countdown with `name`, `duration`, and optional `layout`.
    init(
        id: UUID = UUID(),
        showId: UUID,
        name: String,
        duration: Int,
        layout: CountdownClockLayout = .default,
        background: CountdownBackground = .black,
        endAction: CountdownEndAction = .hold,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.showId = showId
        self.name = name
        self.duration = duration
        self.layout = layout
        self.background = background
        self.endAction = endAction
        self.createdAt = createdAt
    }

    /// Tile caption: name plus remaining or full length.
    func tileTitle(remaining: Int? = nil) -> String {
        let seconds = remaining ?? duration
        return "\(name)\n\(CountdownController.displayString(seconds: seconds))"
    }

    // MARK: - Codable

    private enum CodingKeys: String, CodingKey {
        case id, showId, name, duration, layout, background, endAction, createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        showId = try c.decode(UUID.self, forKey: .showId)
        name = try c.decode(String.self, forKey: .name)
        duration = try c.decode(Int.self, forKey: .duration)
        layout = try c.decodeIfPresent(
            CountdownClockLayout.self, forKey: .layout
        ) ?? .default
        background = try c.decodeIfPresent(
            CountdownBackground.self, forKey: .background
        ) ?? .black
        endAction = try c.decodeIfPresent(
            CountdownEndAction.self, forKey: .endAction
        ) ?? .fallback
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}
