//
//  SyncTombstones.swift
//  Eclipse
//
//  Dated removal markers for a Show's `deletedItemIds` / `deletedSurfaceIds`.
//  Verbatim copy of EclipseSyncKit/SyncTombstones.swift in the Mac repo.
//

import Foundation

/// Reads and writes the entries of a Show's tombstone lists.
///
/// Each entry records the latest membership event for one id:
/// - `id` — removed, time unknown (written by builds before 2026-11-02)
/// - `id@<ms>` — removed at `<ms>` (milliseconds since 1970)
/// - `+id@<ms>` — added back at `<ms>`
///
/// Merging keeps the latest event per id, so Undo or a re-add after the
/// removal has synced wins over the older removal, and a later removal wins
/// over the re-add. A tie keeps the removal.
public enum SyncTombstones {

    // MARK: - Types

    /// One parsed entry.
    public struct Event: Equatable {
        public let id: String
        public let time: Int64
        public let isRemoval: Bool
    }

    // MARK: - Queries

    /// Parses one entry; a plain id is a removal at time 0.
    public static func parse(_ entry: String) -> Event {
        let isRevival = entry.hasPrefix("+")
        let body = isRevival ? String(entry.dropFirst()) : entry
        if let separator = body.lastIndex(of: "@"),
           let time = Int64(body[body.index(after: separator)...]) {
            return Event(id: String(body[..<separator]), time: time, isRemoval: !isRevival)
        }
        return Event(id: body, time: 0, isRemoval: true)
    }

    /// Ids whose latest event is a removal.
    public static func removedIds(_ entries: [String]) -> Set<String> {
        Set(latestEvents(entries).values.filter(\.isRemoval).map(\.id))
    }

    /// Whether `id`'s latest event is a removal.
    public static func isRemoved(_ id: String, in entries: [String]) -> Bool {
        removedIds(entries).contains(id)
    }

    // MARK: - Edits

    /// Records that `id` was removed at `now` (always after its previous event).
    public static func markRemoved(_ id: String, in entries: inout [String], now: Date = Date()) {
        let time = stamp(for: id, in: entries, now: now)
        replace(id, with: "\(id)@\(time)", in: &entries)
    }

    /// Records that `id` was added back at `now`. Ids that were never removed
    /// get no entry, so the lists stay small.
    public static func markAdded(_ id: String, in entries: inout [String], now: Date = Date()) {
        guard entries.contains(where: { parse($0).id == id }) else { return }
        let time = stamp(for: id, in: entries, now: now)
        replace(id, with: "+\(id)@\(time)", in: &entries)
    }

    /// Both lists combined, keeping each id's latest event (in first-seen order).
    public static func merge(_ preferred: [String], _ other: [String]) -> [String] {
        let latest = latestEvents(preferred + other)
        var seen = Set<String>()
        return (preferred + other).compactMap { entry -> String? in
            let id = parse(entry).id
            guard seen.insert(id).inserted, let event = latest[id] else { return nil }
            return encode(event)
        }
    }

    // MARK: - Private Helpers

    private static func latestEvents(_ entries: [String]) -> [String: Event] {
        var latest: [String: Event] = [:]
        for event in entries.map(parse) {
            guard let current = latest[event.id] else {
                latest[event.id] = event
                continue
            }
            let newer = event.time > current.time
            let tieRemoval = event.time == current.time && event.isRemoval
            if newer || tieRemoval { latest[event.id] = event }
        }
        return latest
    }

    private static func encode(_ event: Event) -> String {
        if event.isRemoval, event.time == 0 { return event.id }
        return (event.isRemoval ? "" : "+") + "\(event.id)@\(event.time)"
    }

    private static func replace(_ id: String, with entry: String, in entries: inout [String]) {
        entries.removeAll { parse($0).id == id }
        entries.append(entry)
    }

    /// `now` in milliseconds, nudged past `id`'s latest event so a quick
    /// Undo can never tie with the removal it undoes.
    private static func stamp(for id: String, in entries: [String], now: Date) -> Int64 {
        let previous = latestEvents(entries)[id]?.time ?? -1
        return max(milliseconds(now), previous + 1)
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
