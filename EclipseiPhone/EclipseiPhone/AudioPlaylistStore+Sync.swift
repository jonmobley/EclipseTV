//
//  AudioPlaylistStore+Sync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

// MARK: - iCloud sync of playlists

/// Playlists sync as `AudioPlaylist` records (`playlist-<id>`), shared with the Mac
/// app. The protected Background Music playlist never syncs in either direction.
/// Song ids this device has no file for yet are kept in order, never dropped.
extension AudioPlaylistStore {

    // MARK: - Outgoing

    /// The playlist as it should be sent, or nil when it must not be sent.
    func syncPayload(for id: UUID) -> SyncedAudioPlaylist? {
        guard let playlist = playlist(id: id), MusicSyncPolicy.canSend(playlist) else {
            return nil
        }
        let clock = syncLedger.modifiedAt(id) ?? playlist.createdAt
        return SyncedAudioPlaylist(playlist: playlist, modifiedAt: clock)
    }

    /// Sendable playlists whose latest save the server has not acknowledged.
    var playlistIdsNeedingUpload: [UUID] {
        playlists
            .filter { !syncLedger.isSynced($0.id) && MusicSyncPolicy.canSend($0) }
            .map(\.id)
    }

    /// Records that the server accepted the playlist's save.
    func markPlaylistSynced(id: UUID) {
        syncLedger.markSynced(id)
    }

    /// Forgets every acknowledgement (zone loss, iCloud account switch).
    func markAllPlaylistsNeedUpload() {
        syncLedger.markAllNeedsUpload()
    }

    // MARK: - Incoming

    /// Applies a playlist from iCloud when it is at least as new as the local one
    /// (a tie goes to the remote copy). Protected playlists are ignored.
    /// - Returns: True when the remote copy was applied.
    @discardableResult
    func applyRemote(_ incoming: SyncedAudioPlaylist) -> Bool {
        let remote = incoming.playlist
        guard remote.id != DefaultBackgroundMusic.playlistId else { return false }
        if let local = playlist(id: remote.id) {
            if local.isProtected { return false }
            let localClock = syncLedger.modifiedAt(local.id) ?? local.createdAt
            guard incoming.modifiedAt >= localClock else { return false }
        }
        upsertSyncedPlaylist(AudioPlaylist(
            id: remote.id,
            name: remote.name,
            trackIds: remote.trackIds,
            createdAt: remote.createdAt
        ))
        syncLedger.acceptRemote(remote.id, modifiedAt: incoming.modifiedAt)
        return true
    }

    /// Removes a playlist after an iCloud deletion, without echoing a delete.
    func purgeRemote(id: UUID) {
        guard let existing = playlist(id: id), !existing.isProtected else { return }
        removePlaylist(id: id)
        syncLedger.forget(id)
    }

    // MARK: - Local edit hooks

    /// Stamps a local edit and schedules the playlist's save.
    func noteLocalEdit(id: UUID) {
        guard let playlist = playlist(id: id), MusicSyncPolicy.canSend(playlist),
              !EclipseSyncController.shared.isApplyingRemote else { return }
        syncLedger.stamp(id, at: Date())
        EclipseSyncController.shared.backend.scheduleAudioPlaylistSave(id: id)
    }

    /// Schedules the record deletion for a playlist removed on this device.
    func noteLocalDeletion(id: UUID) {
        syncLedger.forget(id)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleAudioPlaylistDelete(id: id)
    }
}
