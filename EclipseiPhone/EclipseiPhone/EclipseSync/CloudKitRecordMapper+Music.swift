//
//  CloudKitRecordMapper+Music.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// A song as read from (or written to) iCloud, with its last-writer-wins clock.
struct SyncedAudioTrack: Equatable {
    var track: AudioTrack
    var modifiedAt: Date
}

/// A playlist as read from (or written to) iCloud, with its last-writer-wins clock.
struct SyncedAudioPlaylist: Equatable {
    var playlist: AudioPlaylist
    var modifiedAt: Date
}

// MARK: - AudioTrack

extension CloudKitRecordMapper {

    /// Builds an `AudioTrack` record. Never sets `parent`.
    ///
    /// - Parameters:
    ///   - synced: The song and its clock.
    ///   - assetURL: The audio file to upload, or nil when the server already has
    ///     it; the save is then a partial update that keeps the stored asset.
    ///   - existing: The last known server record, for a tagged update.
    /// - Returns: The record to save.
    static func makeAudioTrackRecord(
        from synced: SyncedAudioTrack,
        assetURL: URL?,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let track = synced.track
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.MusicRecordType.audioTrack,
            recordID: CloudKitSchema.audioTrackRecordID(for: track.id)
        )
        typealias Key = CloudKitSchema.AudioTrackKey
        record[Key.title] = track.title as CKRecordValue
        let artist = track.artist?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        record[Key.artist] = artist.isEmpty ? nil : artist as CKRecordValue
        record[Key.duration] = track.duration as CKRecordValue
        record[Key.fileExtension] = track.fileExtension.lowercased() as CKRecordValue
        record[Key.createdAt] = track.createdAt as CKRecordValue
        record[Key.modifiedAt] = synced.modifiedAt as CKRecordValue
        if let assetURL {
            record[Key.asset] = CKAsset(fileURL: assetURL)
        }
        record.parent = nil
        return record
    }

    /// The song in an `AudioTrack` record (the file is handled by the caller).
    ///
    /// The id comes from the record name, so the song keeps one id on every device.
    static func audioTrack(from record: CKRecord) -> SyncedAudioTrack? {
        typealias Key = CloudKitSchema.AudioTrackKey
        guard record.recordType == CloudKitSchema.MusicRecordType.audioTrack,
              let id = CloudKitSchema.audioTrackId(fromRecordName: record.recordID.recordName),
              let title = record[Key.title] as? String,
              let ext = record[Key.fileExtension] as? String,
              !ext.isEmpty
        else { return nil }
        let artist = (record[Key.artist] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let duration = (record[Key.duration] as? Double) ?? 0
        let createdAt = (record[Key.createdAt] as? Date) ?? record.creationDate ?? Date()
        let track = AudioTrack(
            id: id,
            title: UserDisplayName.clamp(title),
            artist: (artist?.isEmpty ?? true) ? nil : artist,
            duration: duration.isFinite && duration > 0 ? duration : 0,
            fileExtension: ext.lowercased(),
            createdAt: createdAt
        )
        return SyncedAudioTrack(track: track, modifiedAt: musicModifiedAt(of: record))
    }

    /// Local temp URL CloudKit staged the song's bytes at, if the record carries them.
    static func audioTrackAssetURL(from record: CKRecord) -> URL? {
        (record[CloudKitSchema.AudioTrackKey.asset] as? CKAsset)?.fileURL
    }
}

// MARK: - AudioPlaylist

extension CloudKitRecordMapper {

    /// Builds an `AudioPlaylist` record. Never sets `parent`. An empty playlist
    /// clears `trackIds` (CloudKit cannot store an empty list).
    static func makeAudioPlaylistRecord(
        from synced: SyncedAudioPlaylist,
        existing: CKRecord? = nil
    ) -> CKRecord {
        let playlist = synced.playlist
        let record = existing ?? CKRecord(
            recordType: CloudKitSchema.MusicRecordType.audioPlaylist,
            recordID: CloudKitSchema.audioPlaylistRecordID(for: playlist.id)
        )
        typealias Key = CloudKitSchema.AudioPlaylistKey
        let name = playlist.name.trimmingCharacters(in: .whitespacesAndNewlines)
        record[Key.name] = UserDisplayName.clamp(name) as CKRecordValue
        let ids = playlist.trackIds.map(\.uuidString)
        record[Key.trackIds] = ids.isEmpty ? nil : ids as CKRecordValue
        record[Key.createdAt] = playlist.createdAt as CKRecordValue
        record[Key.modifiedAt] = synced.modifiedAt as CKRecordValue
        record.parent = nil
        return record
    }

    /// The playlist in an `AudioPlaylist` record. Missing `trackIds` reads as empty;
    /// ids the phone has no song for yet are kept in order.
    static func audioPlaylist(from record: CKRecord) -> SyncedAudioPlaylist? {
        typealias Key = CloudKitSchema.AudioPlaylistKey
        guard record.recordType == CloudKitSchema.MusicRecordType.audioPlaylist,
              let id = CloudKitSchema.audioPlaylistId(
                fromRecordName: record.recordID.recordName
              ),
              let rawName = record[Key.name] as? String,
              let name = UserDisplayName.normalized(rawName)
        else { return nil }
        let rawIds = record[Key.trackIds] as? [String] ?? []
        let playlist = AudioPlaylist(
            id: id,
            name: name,
            trackIds: rawIds.compactMap(UUID.init(uuidString:)),
            createdAt: (record[Key.createdAt] as? Date) ?? record.creationDate ?? Date()
        )
        return SyncedAudioPlaylist(playlist: playlist, modifiedAt: musicModifiedAt(of: record))
    }

    /// Both music record kinds name their clock field `modifiedAt`.
    private static func musicModifiedAt(of record: CKRecord) -> Date {
        (record[CloudKitSchema.AudioTrackKey.modifiedAt] as? Date)
            ?? record.modificationDate
            ?? .distantPast
    }
}
