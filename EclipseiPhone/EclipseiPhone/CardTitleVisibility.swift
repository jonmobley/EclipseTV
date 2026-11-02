//
//  CardTitleVisibility.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import CloudKit
import Foundation

/// Whether a grid tile shows its title, per item (Show / Hide Title).
///
/// Same rule as the Mac app (`MediaManager+CardTitle`): photos, videos,
/// slideshows and PDFs start untitled; websites, polls, countdowns and cameras
/// show their name. A choice made on either app syncs through iCloud as the
/// record's `titleShown` field (absent = never chosen, use the default). Unlike
/// presenter notes it rides on shared-Show records too, so collaborators see
/// the same titles.
enum CardTitleVisibility {
    private static let overridesKey = "EclipseTV.cardTitle.shown"
    /// Ids chosen here whose record has not been saved since; an incoming value
    /// is older than the choice, so it must not undo it.
    private static let pendingKey = "EclipseTV.cardTitle.pending"
    private static let firstUploadKey = "EclipseTV.cardTitle.firstUploadQueued"

    static let didChangeNotification = Notification.Name("CardTitleVisibility.didChange")

    /// Whether the tile for `id` shows its title.
    static func isShown(forId id: String, kind: ThumbnailTypeIcon) -> Bool {
        choice(forId: id) ?? kind.showsTitleByDefault
    }

    /// The user's explicit choice for `id`, or nil when never chosen.
    static func choice(forId id: String) -> Bool? {
        overrides()[id]
    }

    /// Menu title for the Show / Hide Title action.
    static func menuTitle(forId id: String, kind: ThumbnailTypeIcon) -> String {
        isShown(forId: id, kind: kind) ? "Hide Title" : "Show Title"
    }

    /// Saves a choice made on this device; the caller schedules the record save.
    static func setShown(_ shown: Bool, forId id: String) {
        store(shown, forId: id)
        setPending(true, forId: id)
    }

    /// Drops a deleted item's choice so the map does not accumulate dead ids.
    static func clear(forId id: String) {
        var map = overrides()
        guard map.removeValue(forKey: id) != nil else { return }
        UserDefaults.standard.set(map, forKey: overridesKey)
        setPending(false, forId: id)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    // MARK: - iCloud

    /// Writes this device's choice onto `record` (leaves the field alone when
    /// nothing was chosen here, so a Mac choice is not erased).
    static func write(to record: CKRecord, id: String) {
        guard let shown = choice(forId: id) else { return }
        record[CloudKitSchema.titleShownKey] = shown as CKRecordValue
    }

    /// Applies `titleShown` from a fetched record (another device's choice).
    ///
    /// - Parameter hasPendingLocalEdits: The record is still waiting to upload a
    ///   change from here, so the fetched value is the older one.
    static func applyRemote(
        from record: CKRecord,
        id: String,
        hasPendingLocalEdits: Bool = false
    ) {
        guard !hasPendingLocalEdits, !pendingIds().contains(id),
              let shown = record[CloudKitSchema.titleShownKey] as? Bool else { return }
        store(shown, forId: id)
    }

    /// A record carrying `id`'s choice reached iCloud: later fetches may apply.
    static func noteSaved(id: String) {
        setPending(false, forId: id)
    }

    /// Photos and videos titled before titles synced: they were shown on the
    /// iPhone, so they stay shown. Returned once so each is uploaded (with its
    /// title text) a single time; later calls return nothing.
    static func idsNeedingFirstUpload() -> [String] {
        guard !UserDefaults.standard.bool(forKey: firstUploadKey) else { return [] }
        UserDefaults.standard.set(true, forKey: firstUploadKey)
        return keepShown(MediaTitleStore.titledIds())
    }

    /// Marks `ids` shown unless a choice exists, and returns them for upload.
    static func keepShown(_ ids: [String]) -> [String] {
        for id in ids where choice(forId: id) == nil {
            setShown(true, forId: id)
        }
        return ids
    }

    // MARK: - Private

    private static func store(_ shown: Bool, forId id: String) {
        var map = overrides()
        guard map[id] != shown else { return }
        map[id] = shown
        UserDefaults.standard.set(map, forKey: overridesKey)
        NotificationCenter.default.post(name: didChangeNotification, object: id)
    }

    private static func overrides() -> [String: Bool] {
        UserDefaults.standard.dictionary(forKey: overridesKey) as? [String: Bool] ?? [:]
    }

    private static func pendingIds() -> Set<String> {
        Set(UserDefaults.standard.stringArray(forKey: pendingKey) ?? [])
    }

    private static func setPending(_ pending: Bool, forId id: String) {
        var ids = pendingIds()
        let changed = pending ? ids.insert(id).inserted : ids.remove(id) != nil
        guard changed else { return }
        UserDefaults.standard.set(Array(ids), forKey: pendingKey)
    }
}

extension ThumbnailTypeIcon {

    /// Title shown before anyone chooses (the Mac app's `showsTitleByDefault`).
    var showsTitleByDefault: Bool {
        switch self {
        case .photo, .video, .slideshow, .pdf: return false
        case .website, .webVideo, .camera, .ptzCamera, .livePoll, .countdown: return true
        }
    }

    /// Camera tiles have no record to carry a choice, so they always show theirs.
    var canToggleTitle: Bool {
        self != .camera && self != .ptzCamera
    }
}
