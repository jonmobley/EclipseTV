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

    /// Creates a new track bookmark.
    init(
        id: UUID = UUID(),
        title: String,
        artist: String? = nil,
        duration: TimeInterval = 0,
        fileExtension: String,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.title = title
        self.artist = artist
        self.duration = duration
        self.fileExtension = fileExtension
        self.createdAt = createdAt
    }

    /// Display subtitle: artist, or empty.
    var subtitle: String {
        let trimmed = artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed
    }
}
