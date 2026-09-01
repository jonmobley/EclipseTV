//
//  MediaTitleStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Per-item overlay titles keyed by `LibraryItemDTO.id`.
///
/// Phone-local only — never sent on Multipeer or written onto `LibraryItemDTO`,
/// so TV manifest replaces cannot wipe them. Cleared when the media is deleted.
enum MediaTitleStore {
    private static let titlesKey = "EclipseTV.media.titles"

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
        } else {
            let clamped = UserDisplayName.clamp(trimmed)
            if titles[id] == clamped { return }
            titles[id] = clamped
        }
        UserDefaults.standard.set(titles, forKey: titlesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    /// Drops a deleted item's title so the map does not accumulate dead ids.
    static func clear(forId id: String) {
        var titles = storedTitles()
        guard titles.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(titles, forKey: titlesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    // MARK: - Private

    private static func storedTitles() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: titlesKey) as? [String: String] ?? [:]
    }
}
