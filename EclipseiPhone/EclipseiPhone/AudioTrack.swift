//
//  AudioTrack.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// A music file saved for phone playback (phone-only; not sent to the TV app).
struct AudioTrack: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    var title: String
    var artist: String?
    var duration: TimeInterval
    let fileExtension: String
    let createdAt: Date
    /// Bundled / system tracks that cannot be deleted or renamed.
    var isProtected: Bool

    /// Creates a new track bookmark.
    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        duration: TimeInterval = 0,
        fileExtension: String,
        createdAt: Date = Date(),
        isProtected: Bool = false
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileExtension = fileExtension
        self.createdAt = createdAt
        self.isProtected = isProtected
    }

    /// Display subtitle: artist, or empty.
    var subtitle: String {
        let trimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, artist, duration, fileExtension, createdAt, isProtected
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        title = try c.decode(String.self, forKey: .title)
        artist = try c.decodeIfPresent(String.self, forKey: .artist)
        duration = try c.decode(TimeInterval.self, forKey: .duration)
        fileExtension = try c.decode(String.self, forKey: .fileExtension)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        isProtected = try c.decodeIfPresent(Bool.self, forKey: .isProtected) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(artist, forKey: .artist)
        try c.encode(duration, forKey: .duration)
        try c.encode(fileExtension, forKey: .fileExtension)
        try c.encode(createdAt, forKey: .createdAt)
        try c.encode(isProtected, forKey: .isProtected)
    }
}
