//
//  MediaNoteStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// When the Preview note card appears for a still without text.
enum MediaNoteVisibility: String, CaseIterable {
    /// Hide the card until the user adds a note (default).
    case whenExists = "When a note exists"
    /// Always show the card so notes can be added while swiping Preview.
    case always = "Always"

    /// Short label for Settings secondary text.
    var summary: String { rawValue }
}

/// Per-item presenter notes keyed by `LibraryItemDTO.id`.
///
/// Never sent on Multipeer or written onto `LibraryItemDTO`, so TV manifest
/// replaces cannot wipe them. Synced through iCloud on the item's `MediaItem`
/// record (`note`), so the Mac app shows them too. Cleared when the media is
/// deleted.
enum MediaNoteStore {
    private static let notesKey = "EclipseTV.media.notes"
    private static let visibilityKey = "EclipseTV.media.notesVisibility"
    /// Ids whose note the user deleted, so iCloud is told `""` instead of
    /// leaving the old text on other devices.
    private static let clearedKey = "EclipseTV.media.notesCleared"

    static let didChangeNotification = Notification.Name("MediaNoteStore.didChange")

    // MARK: - Notes

    /// Note text for `id`, or `nil` when blank / unset.
    static func note(forId id: String) -> String? {
        let trimmed = storedNotes()[id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmed, !trimmed.isEmpty else { return nil }
        return trimmed
    }

    /// Whether `id` has a non-empty note.
    static func hasNote(forId id: String) -> Bool {
        note(forId: id) != nil
    }

    /// Menu title for the Add / Edit note action.
    static func menuTitle(forId id: String) -> String {
        hasNote(forId: id) ? "Edit note" : "Add note"
    }

    /// Saves `text` for `id`. Whitespace-only or empty removes the entry.
    static func setNote(_ text: String?, forId id: String) {
        var notes = storedNotes()
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            guard notes.removeValue(forKey: id) != nil else { return }
            setCleared(true, forId: id)
        } else if notes[id] == trimmed {
            return
        } else {
            notes[id] = trimmed
            setCleared(false, forId: id)
        }
        UserDefaults.standard.set(notes, forKey: notesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    /// Drops a deleted item's note so the map does not accumulate dead ids.
    static func clear(forId id: String) {
        var notes = storedNotes()
        guard notes.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(notes, forKey: notesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    // MARK: - Visibility

    /// Preview card visibility preference.
    static var visibility: MediaNoteVisibility {
        get {
            guard let raw = UserDefaults.standard.string(forKey: visibilityKey),
                  let value = MediaNoteVisibility(rawValue: raw) else {
                return .whenExists
            }
            return value
        }
        set {
            guard newValue != visibility else { return }
            UserDefaults.standard.set(newValue.rawValue, forKey: visibilityKey)
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    /// Whether the Preview overlay should show for `id` given current prefs.
    static func shouldShowOverlay(forId id: String) -> Bool {
        if hasNote(forId: id) { return true }
        return visibility == .always
    }

    // MARK: - iCloud

    /// What to write to iCloud for `id`: the note, `""` when the user deleted
    /// it, or nil to leave the record's note alone (never had one here).
    static func cloudValue(forId id: String) -> String? {
        if let note = note(forId: id) { return note }
        return clearedIds().contains(id) ? "" : nil
    }

    /// Applies a note from iCloud (another device's edit).
    static func applyRemote(_ text: String, forId id: String) {
        setNote(text, forId: id)
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

    private static func storedNotes() -> [String: String] {
        UserDefaults.standard.dictionary(forKey: notesKey) as? [String: String] ?? [:]
    }
}
