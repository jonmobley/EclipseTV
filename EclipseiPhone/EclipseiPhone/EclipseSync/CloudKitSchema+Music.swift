//
//  CloudKitSchema+Music.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Music (songs + playlists)

/// Record contract shared with the Mac app (2026-11-23). Both record kinds are
/// app-wide and never parented, so they never ride along with a shared Show.
/// Tombstones carry no record type, so the name prefix routes a deletion.
extension CloudKitSchema {

    /// Song and playlist record types.
    enum MusicRecordType {
        static let audioTrack = "AudioTrack"
        static let audioPlaylist = "AudioPlaylist"
    }

    /// Fields of an `AudioTrack` record.
    enum AudioTrackKey {
        static let title = "title"
        /// Absent = no artist.
        static let artist = "artist"
        /// Seconds, as a Double.
        static let duration = "duration"
        /// Lowercased, no dot (mp3, m4a, aac, wav, aif, aiff).
        static let fileExtension = "fileExtension"
        /// The audio file. Later saves may omit it; receivers keep their file.
        static let asset = "asset"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    /// Fields of an `AudioPlaylist` record.
    enum AudioPlaylistKey {
        static let name = "name"
        /// Song UUID strings in play order. Absent = empty.
        static let trackIds = "trackIds"
        static let createdAt = "createdAt"
        static let modifiedAt = "modifiedAt"
    }

    /// Song records are named `audio-<UUID>`.
    static let audioTrackRecordNamePrefix = "audio-"
    /// Playlist records are named `playlist-<UUID>`.
    static let audioPlaylistRecordNamePrefix = "playlist-"

    /// Record ID for a song in the library zone.
    static func audioTrackRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: audioTrackRecordNamePrefix + id.uuidString, zoneID: zoneID)
    }

    /// Record ID for a playlist in the library zone.
    static func audioPlaylistRecordID(for id: UUID) -> CKRecord.ID {
        CKRecord.ID(
            recordName: audioPlaylistRecordNamePrefix + id.uuidString,
            zoneID: zoneID
        )
    }

    /// The song id in an `audio-<UUID>` record name, or nil for any other name.
    static func audioTrackId(fromRecordName name: String) -> UUID? {
        uuid(in: name, afterPrefix: audioTrackRecordNamePrefix)
    }

    /// The playlist id in a `playlist-<UUID>` record name, or nil for any other name.
    static func audioPlaylistId(fromRecordName name: String) -> UUID? {
        uuid(in: name, afterPrefix: audioPlaylistRecordNamePrefix)
    }

    /// Whether `zoneID` is the owner's own private library zone, the only place
    /// music records (and their tombstones) are accepted from.
    static func isPrivateLibraryZone(_ zoneID: CKRecordZone.ID) -> Bool {
        zoneID.zoneName == zoneName && zoneID.ownerName == CKCurrentUserDefaultName
    }

    /// What a tombstone means for music.
    enum MusicDeletion: Equatable {
        /// Remove this song.
        case track(UUID)
        /// Remove this playlist.
        case playlist(UUID)
        /// A music name from another zone (someone else's share): do nothing.
        case ignored
    }

    /// Routes a tombstone by name prefix and zone, or nil when it is not music.
    /// Only the owner's private library zone may remove songs or playlists.
    static func musicDeletion(
        recordName: String,
        zoneID: CKRecordZone.ID
    ) -> MusicDeletion? {
        let trackId = audioTrackId(fromRecordName: recordName)
        let playlistId = audioPlaylistId(fromRecordName: recordName)
        guard trackId != nil || playlistId != nil else { return nil }
        guard isPrivateLibraryZone(zoneID) else { return .ignored }
        if let trackId { return .track(trackId) }
        return playlistId.map(MusicDeletion.playlist)
    }

    private static func uuid(in name: String, afterPrefix prefix: String) -> UUID? {
        guard name.hasPrefix(prefix) else { return nil }
        return UUID(uuidString: String(name.dropFirst(prefix.count)))
    }
}
