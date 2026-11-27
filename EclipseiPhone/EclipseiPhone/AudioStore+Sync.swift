//
//  AudioStore+Sync.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

// MARK: - iCloud sync of songs

/// Songs sync as `AudioTrack` records (`audio-<id>`), shared with the Mac app.
/// Protected (bundled) songs never sync in either direction.
extension AudioStore {

    private static let syncLogger = Logger(
        subsystem: "com.eclipseapp.ios", category: "AudioStore.Sync"
    )

    // MARK: - Outgoing

    /// The song as it should be sent, or nil when it must not be sent.
    func syncPayload(for id: UUID) -> SyncedAudioTrack? {
        guard let track = track(id: id), isSendable(track) else { return nil }
        let clock = syncLedger.modifiedAt(id) ?? track.createdAt
        return SyncedAudioTrack(track: track, modifiedAt: clock)
    }

    /// The file to attach to a save: only until the server has acknowledged the
    /// song, so a rename does not upload the whole file again.
    func syncAssetURL(for id: UUID) -> URL? {
        guard !syncLedger.isSynced(id) else { return nil }
        return fileURL(for: id)
    }

    /// Sendable songs whose latest save the server has not acknowledged.
    var trackIdsNeedingUpload: [UUID] {
        tracks.filter { !syncLedger.isSynced($0.id) && isSendable($0) }.map(\.id)
    }

    /// Records that the server accepted the song's save.
    func markTrackSynced(id: UUID) {
        syncLedger.markSynced(id)
    }

    /// Forgets every acknowledgement (zone loss, iCloud account switch).
    func markAllTracksNeedUpload() {
        syncLedger.markAllNeedsUpload()
    }

    // MARK: - Incoming

    /// Applies a song from iCloud when it is at least as new as the local one.
    ///
    /// A new song needs `assetURL` (its file); an update without one keeps the
    /// existing file. Protected songs and unsupported formats are ignored.
    /// - Returns: True when the remote copy was applied.
    @discardableResult
    func applyRemote(_ incoming: SyncedAudioTrack, assetURL: URL?) -> Bool {
        let remote = incoming.track
        guard MusicSyncPolicy.syncableExtensions.contains(remote.fileExtension),
              remote.id != DefaultBackgroundMusic.trackId
        else { return false }
        if let local = track(id: remote.id) {
            if local.isProtected { return false }
            let localClock = syncLedger.modifiedAt(local.id) ?? local.createdAt
            guard incoming.modifiedAt >= localClock else { return false }
        }
        guard installFile(for: remote, from: assetURL) else { return false }
        let fileExtension = track(id: remote.id)?.fileExtension ?? remote.fileExtension
        upsertSyncedTrack(AudioTrack(
            id: remote.id,
            title: remote.title,
            artist: remote.artist,
            duration: remote.duration,
            fileExtension: fileExtension,
            createdAt: remote.createdAt
        ))
        syncLedger.acceptRemote(remote.id, modifiedAt: incoming.modifiedAt)
        return true
    }

    /// Removes a song after an iCloud deletion, without echoing a delete.
    func purgeRemote(id: UUID) {
        guard let existing = track(id: id), !existing.isProtected else { return }
        removeTrackAndFile(id: id)
        syncLedger.forget(id)
    }

    // MARK: - Local edit hooks

    /// Stamps a local edit and schedules the song's save.
    func noteLocalEdit(id: UUID) {
        guard let track = track(id: id), !track.isProtected,
              !EclipseSyncController.shared.isApplyingRemote else { return }
        syncLedger.stamp(id, at: Date())
        guard isSendable(track) else { return }
        EclipseSyncController.shared.backend.scheduleAudioTrackSave(id: id)
    }

    /// Schedules the record deletion for a song removed on this device.
    func noteLocalDeletion(id: UUID) {
        syncLedger.forget(id)
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleAudioTrackDelete(id: id)
    }

    // MARK: - Private

    private func isSendable(_ track: AudioTrack) -> Bool {
        let bytes = fileURL(for: track.id).flatMap(Self.fileBytes(at:))
        return MusicSyncPolicy.canSend(track, fileBytes: bytes)
    }

    /// Copies the incoming file into place unless this device already has one.
    private func installFile(for track: AudioTrack, from assetURL: URL?) -> Bool {
        if fileURL(for: track.id) != nil { return true }
        guard let assetURL else {
            Self.syncLogger.notice(
                "Remote song \(track.id.uuidString, privacy: .public) has no file yet"
            )
            return false
        }
        let destination = storageURL(for: track.id, fileExtension: track.fileExtension)
        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.copyItem(at: assetURL, to: destination)
            return true
        } catch {
            Self.syncLogger.error("Remote song copy failed: \(error.localizedDescription)")
            return false
        }
    }

    private static func fileBytes(at url: URL) -> Int64? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize.map(Int64.init)
    }
}
