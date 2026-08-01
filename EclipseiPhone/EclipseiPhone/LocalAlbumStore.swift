//
//  LocalAlbumStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists user-created local albums as JSON metadata in UserDefaults.
@MainActor
final class LocalAlbumStore {

    static let shared = LocalAlbumStore()

    /// Posted when the albums list or membership changes.
    static let didChangeNotification = Notification.Name("LocalAlbumStore.didChange")
    /// `userInfo` key for the album id that triggered a change, when known.
    static let changedAlbumIdKey = "changedAlbumId"

    enum StoreError: LocalizedError {
        case emptyName
        case nameTaken

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a name for the Show."
            case .nameTaken: return "Already taken"
            }
        }
    }

    private(set) var albums: [LocalAlbum] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.localAlbums.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "LocalAlbumStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Mutations

    /// Albums that belong to the active Display Mode.
    var albumsForCurrentMode: [LocalAlbum] {
        let mode = ExternalOutputSettings.orientation
        return albums.filter { $0.orientation == mode }
    }

    /// Every album for cross-mode pickers: active Display Mode first, then the other.
    var albumsActiveModeFirst: [LocalAlbum] {
        let mode = ExternalOutputSettings.orientation
        return albums.filter { $0.orientation == mode }
            + albums.filter { $0.orientation != mode }
    }

    /// Creates an empty album in `orientation` and inserts it at the front.
    @discardableResult
    func create(
        name: String,
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) throws -> LocalAlbum {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard !isNameTaken(trimmed) else { throw StoreError.nameTaken }
        let album = LocalAlbum(
            name: trimmed,
            orientation: orientation,
            lastOpenedAt: Date()
        )
        albums.insert(album, at: 0)
        persist(changedAlbumId: album.id)
        scheduleShowSaveIfNeeded(album.id)
        return album
    }

    /// Moves a Show into `orientation` (e.g. Landscape ↔ Vertical with Display Mode).
    func setOrientation(id: UUID, orientation: ExternalOutputOrientation) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        guard albums[index].orientation != orientation else { return }
        albums[index].orientation = orientation
        persist(changedAlbumId: id)
        scheduleShowSaveIfNeeded(id)
    }

    /// Renames the album with `id` when present.
    func rename(id: UUID, to name: String) throws {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard !isNameTaken(trimmed, excluding: id) else { throw StoreError.nameTaken }
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        albums[index].name = trimmed
        persist(changedAlbumId: id)
        scheduleShowSaveIfNeeded(id)
    }

    /// True when another Show already uses `name` (case-insensitive).
    /// - Parameter excluding: Album id allowed to keep this name (rename of self).
    func isNameTaken(_ name: String, excluding: UUID? = nil) -> Bool {
        guard let trimmed = UserDisplayName.normalized(name) else { return false }
        return albums.contains {
            $0.id != excluding
                && $0.name.compare(trimmed, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
        }
    }

    /// First free title: `Name`, then `Name (2)`, `Name (3)`, …
    ///
    /// Used when a joined/synced Show would collide with one already on this phone.
    func uniquifiedName(_ name: String, excluding: UUID? = nil) -> String {
        let base = UserDisplayName.normalized(name) ?? "Show"
        if !isNameTaken(base, excluding: excluding) { return base }
        var n = 2
        while n < 10_000 {
            let suffix = " (\(n))"
            let budget = max(1, UserDisplayName.maxLength - suffix.count)
            let candidate = UserDisplayName.clamp(String(base.prefix(budget)) + suffix)
            if !isNameTaken(candidate, excluding: excluding) { return candidate }
            n += 1
        }
        return UserDisplayName.clamp("\(base) \(UUID().uuidString.prefix(4))")
    }

    /// Deletes the album with `id` when present.
    func delete(id: UUID) {
        let removed = albums.first(where: { $0.id == id })
        let before = albums.count
        albums.removeAll { $0.id == id }
        guard albums.count != before else { return }
        persist()
        if !EclipseSyncController.shared.isApplyingRemote {
            EclipseSyncController.shared.backend.scheduleShowDelete(id: id)
        }
        // Slideshows are keyed by showId, so they are unreachable once the Show is gone.
        // This has to live here rather than at the confirm-delete alerts: a Show deleted
        // on another device arrives through the sync layer, which never sees that UI.
        SlideshowStore.shared.deleteAll(forShowId: id)
        for itemId in removed?.itemIds ?? [] {
            if let pageId = UUID(uuidString: itemId) {
                WebPageStore.shared.purgeRetainedIfUnused(id: pageId)
            }
        }
    }

    /// Moves `id` to the front so it leads the Recent Shows ribbon.
    func touchRecentlyOpened(id: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == id }) else { return }
        var album = albums.remove(at: index)
        album.lastOpenedAt = Date()
        albums.insert(album, at: 0)
        persist(changedAlbumId: id)
    }

    /// Appends `itemId` to the album if it is not already a member.
    func add(itemId: String, toAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard !albums[index].itemIds.contains(itemId) else { return }
        albums[index].itemIds.append(itemId)
        if var surface = albums[index].surfaceIds {
            if !surface.contains(itemId) { surface.append(itemId) }
            albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
                surface, itemIds: albums[index].itemIds
            )
        }
        if albums[index].coverId == nil {
            albums[index].coverId = itemId
        }
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Removes `itemId` from the album when present.
    func remove(itemId: String, fromAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].itemIds.removeAll { $0 == itemId }
        if var surface = albums[index].surfaceIds {
            surface.removeAll { $0 == itemId }
            albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
                surface, itemIds: albums[index].itemIds
            )
        }
        if albums[index].coverId == itemId {
            albums[index].coverId = albums[index].itemIds.first
        }
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
        if let pageId = UUID(uuidString: itemId) {
            WebPageStore.shared.purgeRetainedIfUnused(id: pageId)
        }
    }

    /// Replaces the album's ordered membership.
    func reorder(itemIds: [String], inAlbumId albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        albums[index].itemIds = itemIds
        if let surface = albums[index].surfaceIds {
            albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
                surface, itemIds: itemIds
            )
        }
        if let cover = albums[index].coverId, !itemIds.contains(cover) {
            albums[index].coverId = itemIds.first
        }
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Hides a tool tile from this Show (materializes surface if needed).
    func hideTool(_ token: String, albumId: UUID) {
        guard ShowToolToken.isTool(token),
              let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        materializeSurface(at: index)
        var surface = albums[index].surfaceIds ?? []
        let before = surface.count
        surface.removeAll { $0 == token }
        guard surface.count != before else { return }
        albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
            surface, itemIds: albums[index].itemIds
        )
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Restores a tool tile at the end of this Show's surface.
    func showTool(_ token: String, albumId: UUID) {
        guard ShowToolToken.isTool(token),
              let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        materializeSurface(at: index)
        var surface = albums[index].surfaceIds ?? []
        guard !surface.contains(token) else { return }
        surface.append(token)
        albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
            surface, itemIds: albums[index].itemIds
        )
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Replaces the Show grid order (tools + members). Syncs `itemIds` to member order.
    func reorderSurface(_ surfaceIds: [String], albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        let sanitized = LocalAlbum.sanitizedSurface(surfaceIds, itemIds: albums[index].itemIds)
        albums[index].surfaceIds = sanitized
        let members = sanitized.filter { !ShowToolToken.isTool($0) }
        // Preserve membership set; order follows surface for members that appear.
        let memberSet = Set(albums[index].itemIds)
        let ordered = members.filter { memberSet.contains($0) }
        let orphans = albums[index].itemIds.filter { !ordered.contains($0) }
        albums[index].itemIds = ordered + orphans
        if let cover = albums[index].coverId, !albums[index].itemIds.contains(cover) {
            albums[index].coverId = albums[index].itemIds.first
        }
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Writes the default surface so later hide/show edits persist.
    private func materializeSurface(at index: Int) {
        guard albums[index].surfaceIds == nil else { return }
        albums[index].surfaceIds = ShowToolToken.all + albums[index].itemIds
    }

    /// Sets the cover thumbnail for `albumId` when `itemId` is a member.
    func setCover(itemId: String, albumId: UUID) {
        guard let index = albums.firstIndex(where: { $0.id == albumId }) else { return }
        guard albums[index].itemIds.contains(itemId) else { return }
        guard albums[index].coverId != itemId else { return }
        albums[index].coverId = itemId
        persist(changedAlbumId: albumId)
        scheduleShowSaveIfNeeded(albumId)
    }

    /// Drops `itemId` from every album (e.g. after library delete).
    func removeItemFromAllAlbums(itemId: String) {
        var changedIds: [UUID] = []
        for index in albums.indices {
            let before = albums[index].itemIds.count
            albums[index].itemIds.removeAll { $0 == itemId }
            if var surface = albums[index].surfaceIds {
                surface.removeAll { $0 == itemId }
                albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
                    surface, itemIds: albums[index].itemIds
                )
            }
            guard albums[index].itemIds.count != before else { continue }
            changedIds.append(albums[index].id)
            if albums[index].coverId == itemId {
                albums[index].coverId = albums[index].itemIds.first
            }
        }
        guard !changedIds.isEmpty else { return }
        persist()
        for id in changedIds {
            scheduleShowSaveIfNeeded(id)
        }
        if let pageId = UUID(uuidString: itemId) {
            WebPageStore.shared.purgeRetainedIfUnused(id: pageId)
        }
    }

    /// Removes membership ids that are no longer in the library.
    ///
    /// Capture library ids, saved website ids (list + Show-retained), and saved PDF
    /// ids are always kept — they are phone-owned and must not be stripped when an
    /// Apple TV manifest omits them.
    func pruneMissingItems(keeping validIds: Set<String>) {
        let captureKeep = CaptureStore.shared.keepIds
        let webKeep = WebPageStore.shared.keepIds
        let pdfKeep = PDFStore.shared.keepIds
        let keep = validIds.union(captureKeep).union(webKeep).union(pdfKeep)
        var changedIds: [UUID] = []
        for index in albums.indices {
            let before = albums[index].itemIds
            let after = before.filter { keep.contains($0) }
            guard after != before else { continue }
            albums[index].itemIds = after
            if let surface = albums[index].surfaceIds {
                albums[index].surfaceIds = LocalAlbum.sanitizedSurface(
                    surface, itemIds: after
                )
            }
            changedIds.append(albums[index].id)
            if let cover = albums[index].coverId, !after.contains(cover) {
                albums[index].coverId = after.first
            }
        }
        guard !changedIds.isEmpty else { return }
        persist()
        for id in changedIds {
            scheduleShowSaveIfNeeded(id)
        }
    }

    /// Album with `id`, if any.
    func album(id: UUID) -> LocalAlbum? {
        albums.first { $0.id == id }
    }

    /// Inserts or replaces an album from CloudKit without scheduling a local-originated save.
    ///
    /// Callers that own the sync engine should set `isApplyingRemote` around this so the
    /// store's `didChange` observer does not immediately re-upload.
    ///
    /// Joined Shows that share a title with a local Show get a `(2)`-style suffix so
    /// Home never lists two identical names.
    func applySynced(_ album: LocalAlbum, modifiedAt: Date) {
        _ = modifiedAt
        var incoming = album
        incoming.name = uniquifiedName(album.name, excluding: album.id)
        if let index = albums.firstIndex(where: { $0.id == incoming.id }) {
            albums[index] = incoming
        } else {
            albums.insert(incoming, at: 0)
        }
        persist(changedAlbumId: incoming.id)
    }

    private func scheduleShowSaveIfNeeded(_ id: UUID) {
        guard !EclipseSyncController.shared.isApplyingRemote else { return }
        EclipseSyncController.shared.backend.scheduleShowSave(id: id)
    }

    // MARK: - Persistence

    private func load() {
        albums = SalvagingListDecoder.decodeList(
            LocalAlbum.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    /// - Parameter changedAlbumId: When known, lets observers scope work to one Show
    ///   instead of re-uploading every album on any mutation.
    private func persist(changedAlbumId: UUID? = nil) {
        do {
            let data = try JSONEncoder().encode(albums)
            defaults.set(data, forKey: itemsKey)
            var info: [AnyHashable: Any]?
            if let changedAlbumId {
                info = [Self.changedAlbumIdKey: changedAlbumId]
            }
            NotificationCenter.default.post(
                name: Self.didChangeNotification,
                object: self,
                userInfo: info
            )
        } catch {
            logger.error("Failed to encode local albums: \(error.localizedDescription)")
        }
    }
}
