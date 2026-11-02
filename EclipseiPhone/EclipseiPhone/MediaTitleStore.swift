//
//  MediaTitleStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Per-item overlay titles keyed by `LibraryItemDTO.id`.
///
/// Never sent on Multipeer or written onto `LibraryItemDTO`, so TV manifest
/// replaces cannot wipe them. Synced through iCloud as the `MediaItem` record's
/// `displayName`, which the Mac app shows as the card title. Cleared when the
/// media is deleted.
enum MediaTitleStore {
    private static let titlesKey = "EclipseTV.media.titles"
    /// Ids whose title the user removed here, so iCloud drops the old name
    /// instead of sending it back on the next fetch.
    private static let clearedKey = "EclipseTV.media.titlesCleared"

    static let didChangeNotification = Notification.Name("MediaTitleStore.didChange")

    /// Overlay title for `id`, or `nil` when blank / unset.
    static func title(forId id: String) -> String? {
        let trimmed = storedTitles()[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return UserDisplayName.clamp(trimmed)
    }

    /// Whether `id` has a non-empty overlay title.
    static func hasTitle(forId id: String) -> Bool {
        title(forId: id) != nil
    }

    /// Overlay title if the user set one, else the item's own name.
    ///
    /// For chrome that always needs something to show, such as the video Preview
    /// title. Matches the precedence VoiceOver reads on library tiles.
    static func displayTitle(for item: LibraryItemDTO) -> String {
        title(forId: item.id) ?? item.name
    }

    /// Menu title for the Add / Edit title action.
    static func menuTitle(forId id: String) -> String {
        hasTitle(forId: id) ? "Edit title" : "Add title"
    }

    /// Saves `text` for `id`. Whitespace-only or empty removes the entry.
    static func setTitle(_ text: String?, forId id: String) {
        var titles = storedTitles()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            guard titles.removeValue(forKey: id) != nil else { return }
            setCleared(true, forId: id)
        } else {
            let clamped = UserDisplayName.clamp(trimmed)
            if titles[id] == clamped { return }
            titles[id] = clamped
            setCleared(false, forId: id)
        }
        UserDefaults.standard.set(titles, forKey: titlesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    /// Drops a deleted item's title so the map does not accumulate dead ids.
    static func clear(forId id: String) {
        setCleared(false, forId: id)
        var titles = storedTitles()
        guard titles.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(titles, forKey: titlesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    /// Ids that have a title (for the one-time upload).
    static func titledIds() -> [String] {
        storedTitles().keys.filter { hasTitle(forId: $0) }
    }

    // MARK: - iCloud

    /// Writes the title onto a MediaItem record as `displayName`: the title,
    /// removed when the user deleted it here, or left alone otherwise (so a
    /// name set on the Mac survives).
    static func write(to record: CKRecord, id: String) {
        if let title = title(forId: id) {
            record[CloudKitSchema.MediaKey.displayName] = title as CKRecordValue
        } else if clearedIds().contains(id) {
            record[CloudKitSchema.MediaKey.displayName] = nil
        }
    }

    /// Applies a title from iCloud (another device's name for the item).
    static func applyRemote(_ text: String, forId id: String) {
        setTitle(text, forId: id)
        setCleared(false, forId: id)
    }

    // MARK: - Private

    private static func clearedIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: clearedKey) ?? [])
    }

    private static func setCleared(_ cleared: Bool, forId id: String) {
        var ids = clearedIds()
        let changed = cleared ? ids.insert(id).inserted : ids.remove(id) != nil
        guard changed else { return }
        UserDefaults.standard.set(Array(ids), forKey: clearedKey)
    }

    private static func storedTitles() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: titlesKey) as? [String: String] ?? [:]
    }
}
