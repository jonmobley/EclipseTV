//
//  MusicSyncPolicy.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Pure rules for which songs and playlists go through iCloud.
///
/// Shared contract with the Mac app: protected (bundled) items never sync, only
/// common audio formats sync, and files must be 1 byte to 200 MB. Stateless, so
/// safe from any thread.
enum MusicSyncPolicy {

    /// Extensions both apps can play. `caf` imports stay on the phone.
    static let syncableExtensions: Set<String> = ["mp3", "m4a", "aac", "wav", "aif", "aiff"]

    /// Largest song file sent to iCloud (same as the import cap).
    static let maxFileBytes: Int64 = 200_000_000

    /// Whether `track` (with a file of `fileBytes`) may be sent to iCloud.
    /// - Parameters:
    ///   - track: The local song.
    ///   - fileBytes: Size of its file, or nil when the file is missing.
    /// - Returns: True for unprotected songs in a syncable format and size.
    static func canSend(_ track: AudioTrack, fileBytes: Int64?) -> Bool {
        guard !track.isProtected, track.id != DefaultBackgroundMusic.trackId else {
            return false
        }
        guard syncableExtensions.contains(track.fileExtension.lowercased()) else {
            return false
        }
        guard let fileBytes else { return false }
        return fileBytes >= 1 && fileBytes <= maxFileBytes
    }

    /// Whether `playlist` may be sent to iCloud (never the protected Background Music).
    static func canSend(_ playlist: AudioPlaylist) -> Bool {
        !playlist.isProtected && playlist.id != DefaultBackgroundMusic.playlistId
    }

    /// Applies a reorder of the songs the phone can show while keeping songs it
    /// cannot show yet (still downloading from another device) in their slots.
    ///
    /// - Parameters:
    ///   - existing: The stored order, including ids the phone has no file for.
    ///   - reordered: The new order of (a subset of) those ids, as the UI shows it.
    /// - Returns: `existing` with the slots of `reordered` ids refilled in the new
    ///   order; ids new to the list are appended.
    static func mergeOrder(existing: [UUID], reordered: [UUID]) -> [UUID] {
        let moved = Set(reordered)
        var queue = reordered[...]
        var result: [UUID] = []
        for id in existing {
            if moved.contains(id) {
                if let next = queue.popFirst() { result.append(next) }
            } else {
                result.append(id)
            }
        }
        result.append(contentsOf: queue)
        return result
    }
}
