//
//  SlideshowStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation
import os.log

/// Persists user-created slideshows as JSON metadata in UserDefaults.
@MainActor
final class SlideshowStore {

    static let shared = SlideshowStore()

    /// Posted when slideshows change.
    static let didChangeNotification = Notification.Name("SlideshowStore.didChange")

    enum StoreError: LocalizedError {
        case emptyName
        case noImages

        var errorDescription: String? {
            switch self {
            case .emptyName: return "Enter a name for the Slideshow."
            case .noImages: return "Pick at least one image."
            }
        }
    }

    private(set) var slideshows: [Slideshow] = []

    private let defaults: UserDefaults
    private let itemsKey = "EclipseTV.slideshows.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "SlideshowStore")

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    /// Slideshows belonging to `showId`, newest first.
    func slideshows(forShowId showId: UUID) -> [Slideshow] {
        slideshows.filter { $0.showId == showId }
    }

    /// Slideshow with `id`, if any.
    func slideshow(id: UUID) -> Slideshow? {
        slideshows.first { $0.id == id }
    }

    // MARK: - Mutations

    /// Creates a slideshow and appends it (last among this Show's slideshows).
    @discardableResult
    func create(
        name: String,
        showId: UUID,
        itemIds: [String],
        orientation: ExternalOutputOrientation = ExternalOutputSettings.orientation
    ) throws -> Slideshow {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard !itemIds.isEmpty else { throw StoreError.noImages }
        let show = Slideshow(
            showId: showId,
            name: trimmed,
            itemIds: itemIds,
            coverId: itemIds.first,
            orientation: orientation
        )
        slideshows.append(show)
        persist()
        return show
    }

    /// Aligns every slideshow under `showId` with the Show's Display Mode format.
    func setOrientation(_ orientation: ExternalOutputOrientation, forShowId showId: UUID) {
        var changed = false
        for index in slideshows.indices where slideshows[index].showId == showId {
            guard slideshows[index].orientation != orientation else { continue }
            slideshows[index].orientation = orientation
            changed = true
        }
        if changed { persist() }
    }

    /// Renames the slideshow with `id` when present.
    func rename(id: UUID, to name: String) throws {
        guard let trimmed = UserDisplayName.normalized(name) else {
            throw StoreError.emptyName
        }
        guard let index = slideshows.firstIndex(where: { $0.id == id }) else { return }
        slideshows[index].name = trimmed
        persist()
    }

    /// Deletes the slideshow with `id` when present.
    func delete(id: UUID) {
        let before = slideshows.count
        slideshows.removeAll { $0.id == id }
        guard slideshows.count != before else { return }
        SlideshowPlaybackController.shared.clearResume(for: id)
        persist()
    }

    /// Deletes every slideshow belonging to `showId`.
    func deleteAll(forShowId showId: UUID) {
        let before = slideshows.count
        slideshows.removeAll { $0.showId == showId }
        guard slideshows.count != before else { return }
        persist()
    }

    /// Replaces ordered membership for `id`.
    func reorder(itemIds: [String], inSlideshowId id: UUID) {
        guard let index = slideshows.firstIndex(where: { $0.id == id }) else { return }
        slideshows[index].itemIds = itemIds
        if let cover = slideshows[index].coverId, !itemIds.contains(cover) {
            slideshows[index].coverId = itemIds.first
        }
        persist()
    }

    /// Removes `itemId` from the slideshow when present.
    func remove(itemId: String, fromSlideshowId id: UUID) {
        guard let index = slideshows.firstIndex(where: { $0.id == id }) else { return }
        slideshows[index].itemIds.removeAll { $0 == itemId }
        if slideshows[index].coverId == itemId {
            slideshows[index].coverId = slideshows[index].itemIds.first
        }
        persist()
    }

    /// Sets the cover thumbnail when `itemId` is a member.
    func setCover(itemId: String, slideshowId id: UUID) {
        guard let index = slideshows.firstIndex(where: { $0.id == id }) else { return }
        guard slideshows[index].itemIds.contains(itemId) else { return }
        guard slideshows[index].coverId != itemId else { return }
        slideshows[index].coverId = itemId
        persist()
    }

    /// Updates playback preferences for `id`.
    func updatePreferences(
        id: UUID,
        autoplay: Bool? = nil,
        autoplaySeconds: SlideshowAutoplaySeconds? = nil,
        loop: Bool? = nil,
        crossfade: Bool? = nil,
        showRibbonWhenLive: Bool? = nil
    ) {
        guard let index = slideshows.firstIndex(where: { $0.id == id }) else { return }
        if let autoplay { slideshows[index].autoplay = autoplay }
        if let autoplaySeconds { slideshows[index].autoplaySeconds = autoplaySeconds }
        if let loop { slideshows[index].loop = loop }
        if let crossfade { slideshows[index].crossfade = crossfade }
        if let showRibbonWhenLive {
            slideshows[index].showRibbonWhenLive = showRibbonWhenLive
        }
        persist()
    }

    /// Drops `itemId` from every slideshow (e.g. after library delete).
    func removeItemFromAllSlideshows(itemId: String) {
        var changed = false
        for index in slideshows.indices {
            let before = slideshows[index].itemIds.count
            slideshows[index].itemIds.removeAll { $0 == itemId }
            guard slideshows[index].itemIds.count != before else { continue }
            changed = true
            if slideshows[index].coverId == itemId {
                slideshows[index].coverId = slideshows[index].itemIds.first
            }
        }
        if changed { persist() }
    }

    /// Removes membership ids that are no longer in the library.
    func pruneMissingItems(keeping validIds: Set<String>) {
        var changed = false
        for index in slideshows.indices {
            let before = slideshows[index].itemIds
            let after = before.filter { validIds.contains($0) }
            guard after != before else { continue }
            slideshows[index].itemIds = after
            changed = true
            if let cover = slideshows[index].coverId, !after.contains(cover) {
                slideshows[index].coverId = after.first
            }
        }
        if changed { persist() }
    }

    // MARK: - Persistence

    private func load() {
        slideshows = SalvagingListDecoder.decodeList(
            Slideshow.self,
            forKey: itemsKey,
            from: defaults,
            logger: logger
        ).elements
    }

    private func persist() {
        do {
            let data = try JSONEncoder().encode(slideshows)
            defaults.set(data, forKey: itemsKey)
            NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
        } catch {
            logger.error("Failed to encode slideshows: \(error.localizedDescription)")
        }
    }
}
