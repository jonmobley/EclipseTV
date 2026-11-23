//
//  MusicUpNext.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Songs lined up with Play Next / Add to Queue, played before the rest of the
/// playlist (or Music list) carries on. Same rules as the Mac's `MusicQueue`:
///
/// - A song is in Up Next at most once.
/// - Play Next puts a song first (moving it there if it was already queued).
/// - Add to Queue puts a song last, and leaves an already-queued song where it is.
///
/// Unlike the Mac, the list can be reordered. It lasts for the session only.
struct MusicUpNext: Equatable {

    private(set) var trackIds: [UUID] = []

    var isEmpty: Bool { trackIds.isEmpty }
    var count: Int { trackIds.count }

    func contains(_ id: UUID) -> Bool { trackIds.contains(id) }

    /// Puts `id` first, moving it there if it was already queued.
    mutating func playNext(_ id: UUID) {
        trackIds.removeAll { $0 == id }
        trackIds.insert(id, at: 0)
    }

    /// Puts `id` last unless it is already queued (it keeps its place).
    mutating func add(_ id: UUID) {
        guard !contains(id) else { return }
        trackIds.append(id)
    }

    mutating func remove(_ id: UUID) {
        trackIds.removeAll { $0 == id }
    }

    /// Removes and returns the song at `index`, or `nil` when out of range.
    mutating func remove(at index: Int) -> UUID? {
        guard trackIds.indices.contains(index) else { return nil }
        return trackIds.remove(at: index)
    }

    mutating func move(from source: Int, to destination: Int) {
        guard trackIds.indices.contains(source) else { return }
        let id = trackIds.remove(at: source)
        trackIds.insert(id, at: min(max(0, destination), trackIds.count))
    }

    mutating func removeAll() {
        trackIds.removeAll()
    }

    /// Removes and returns the first song that `isPlayable` accepts, dropping any
    /// unplayable songs ahead of it (deleted files).
    mutating func popFirst(where isPlayable: (UUID) -> Bool) -> UUID? {
        while !trackIds.isEmpty {
            let id = trackIds.removeFirst()
            if isPlayable(id) { return id }
        }
        return nil
    }
}
