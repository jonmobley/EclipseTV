//
//  CloudKitSyncEngine+Music.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

// MARK: - Music (songs + playlists)

/// Wires `AudioStore` / `AudioPlaylistStore` into the sync engine. Like the
/// Prompter, these records are app-wide and never parented, so only this user's
/// own private records are applied.
extension CloudKitSyncEngine {

    // MARK: - Schedules

    /// Schedules a song upload.
    func scheduleAudioTrackSave(id: UUID) {
        scheduleSave(CloudKitSchema.audioTrackRecordID(for: id))
    }

    /// Schedules deletion of a song record.
    func scheduleAudioTrackDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.audioTrackRecordID(for: id))
    }

    /// Schedules a playlist upload.
    func scheduleAudioPlaylistSave(id: UUID) {
        scheduleSave(CloudKitSchema.audioPlaylistRecordID(for: id))
    }

    /// Schedules deletion of a playlist record.
    func scheduleAudioPlaylistDelete(id: UUID) {
        scheduleDelete(CloudKitSchema.audioPlaylistRecordID(for: id))
    }

    // MARK: - Outgoing

    /// Whether `name` is a song or playlist record name.
    static func isMusicRecordName(_ name: String) -> Bool {
        CloudKitSchema.audioTrackId(fromRecordName: name) != nil
            || CloudKitSchema.audioPlaylistId(fromRecordName: name) != nil
    }

    /// The record for a pending music save, or nil to skip it (protected, missing,
    /// unsupported format or size).
    func makeMusicRecordToSave(name: String, existing: CKRecord?) -> CKRecord? {
        if let id = CloudKitSchema.audioTrackId(fromRecordName: name) {
            guard let payload = AudioStore.shared.syncPayload(for: id) else { return nil }
            return CloudKitRecordMapper.makeAudioTrackRecord(
                from: payload,
                assetURL: AudioStore.shared.syncAssetURL(for: id),
                existing: existing
            )
        }
        if let id = CloudKitSchema.audioPlaylistId(fromRecordName: name) {
            guard let payload = AudioPlaylistStore.shared.syncPayload(for: id) else {
                return nil
            }
            return CloudKitRecordMapper.makeAudioPlaylistRecord(
                from: payload, existing: existing
            )
        }
        return nil
    }

    /// Enqueues songs and playlists the server has not acknowledged yet.
    func enqueueMusicContent(into changes: inout [CKSyncEngine.PendingRecordZoneChange]) {
        for id in AudioStore.shared.trackIdsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.audioTrackRecordID(for: id)))
        }
        for id in AudioPlaylistStore.shared.playlistIdsNeedingUpload {
            changes.append(.saveRecord(CloudKitSchema.audioPlaylistRecordID(for: id)))
        }
    }

    /// Forgets every music acknowledgement (zone loss, iCloud account switch).
    func markMusicNeedsUpload() {
        AudioStore.shared.markAllTracksNeedUpload()
        AudioPlaylistStore.shared.markAllPlaylistsNeedUpload()
    }

    // MARK: - Incoming

    /// Applies a fetched song or playlist record. Returns false for other types.
    /// Only the owner's own unparented records in the private library zone apply.
    @discardableResult
    func applyRemoteMusic(_ record: CKRecord) -> Bool {
        let isOwn = CloudKitRecordMapper.isPrivateToMe(record)
            && CloudKitSchema.isPrivateLibraryZone(record.recordID.zoneID)
        switch record.recordType {
        case CloudKitSchema.MusicRecordType.audioTrack:
            if isOwn, let synced = CloudKitRecordMapper.audioTrack(from: record) {
                AudioStore.shared.applyRemote(
                    synced, assetURL: CloudKitRecordMapper.audioTrackAssetURL(from: record)
                )
            }
            return true
        case CloudKitSchema.MusicRecordType.audioPlaylist:
            if isOwn, let synced = CloudKitRecordMapper.audioPlaylist(from: record) {
                AudioPlaylistStore.shared.applyRemote(synced)
            }
            return true
        default:
            return false
        }
    }

    /// Clears the dirty state of a saved music record. Returns false for other types.
    @discardableResult
    func markMusicRecordSynced(_ record: CKRecord) -> Bool {
        let name = record.recordID.recordName
        if let id = CloudKitSchema.audioTrackId(fromRecordName: name) {
            AudioStore.shared.markTrackSynced(id: id)
            return true
        }
        if let id = CloudKitSchema.audioPlaylistId(fromRecordName: name) {
            AudioPlaylistStore.shared.markPlaylistSynced(id: id)
            return true
        }
        return false
    }

    /// Re-queues a music save after a conflict. Returns false for other names.
    @discardableResult
    func requeueMusicSave(recordName name: String) -> Bool {
        if let id = CloudKitSchema.audioTrackId(fromRecordName: name) {
            scheduleAudioTrackSave(id: id)
            return true
        }
        if let id = CloudKitSchema.audioPlaylistId(fromRecordName: name) {
            scheduleAudioPlaylistSave(id: id)
            return true
        }
        return false
    }
}
