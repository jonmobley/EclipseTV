//
//  MediaOverlayStore.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Photos and videos the operator chose "Use as Overlay" for:
//               where each sits (center + scale) and its draw order. Local to
//               this phone; nothing here syncs.
//  Thread Safety: Main actor only.
//

import Foundation
import os.log

// MARK: - MediaOverlayEntry

/// A photo or video shown as a layered overlay on top of the live picture.
///
/// Placement uses the Mac's normalized center/scale shape: `centerX`/`centerY`
/// are `0...1` of the output frame, `scale` is the overlay's width as a
/// fraction of the output width.
struct MediaOverlayEntry: Codable, Equatable, Identifiable {

    // MARK: - Constants

    /// Width fraction a new overlay starts at (a third of the screen).
    static let defaultScale: Double = 0.35
    /// Allowed width fractions.
    static let scaleRange: ClosedRange<Double> = 0.1...1

    // MARK: - Properties

    /// Library media id (`LibraryItemDTO.id`).
    let itemId: String
    var isVideo: Bool
    var centerX: Double
    var centerY: Double
    var scale: Double
    /// Draw order among live overlays; higher draws on top.
    var stackOrder: Int

    var id: String { itemId }

    /// Copy with the center kept on screen and the scale in range.
    func clamped() -> MediaOverlayEntry {
        var copy = self
        copy.centerX = min(1, max(0, centerX))
        copy.centerY = min(1, max(0, centerY))
        copy.scale = min(Self.scaleRange.upperBound, max(Self.scaleRange.lowerBound, scale))
        return copy
    }
}

// MARK: - MediaOverlayStore

/// Remembers which photos/videos are overlays and how they are placed.
@MainActor
final class MediaOverlayStore {

    // MARK: - Properties

    static let shared = MediaOverlayStore()

    /// Posted when an entry is added, moved, or removed.
    static let didChangeNotification = Notification.Name("MediaOverlayStore.didChange")

    private(set) var entries: [MediaOverlayEntry] = []

    private let defaults: UserDefaults
    private let key = "EclipseTV.mediaOverlays.items"
    private let logger = Logger(subsystem: "com.eclipseapp.ios", category: "MediaOverlayStore")

    // MARK: - Initialization

    /// Loads saved entries from `defaults`.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

    // MARK: - Queries

    /// Entry for `itemId`, if that media is set up as an overlay.
    func entry(for itemId: String) -> MediaOverlayEntry? {
        entries.first { $0.itemId == itemId }
    }

    // MARK: - Mutations

    /// Sets up `itemId` as a centered overlay above `minimumStackOrder`.
    ///
    /// - Returns: The existing entry when the media is already an overlay.
    @discardableResult
    func add(itemId: String, isVideo: Bool, minimumStackOrder: Int) -> MediaOverlayEntry {
        if let existing = entry(for: itemId) { return existing }
        let top = (entries.map(\.stackOrder).max() ?? -1) + 1
        let entry = MediaOverlayEntry(
            itemId: itemId,
            isVideo: isVideo,
            centerX: 0.5,
            centerY: 0.5,
            scale: MediaOverlayEntry.defaultScale,
            stackOrder: max(top, minimumStackOrder)
        )
        entries.append(entry)
        persist()
        return entry
    }

    /// Saves a new center/scale for an existing entry.
    func update(_ entry: MediaOverlayEntry) {
        guard let index = entries.firstIndex(where: { $0.itemId == entry.itemId }) else { return }
        let next = entry.clamped()
        guard entries[index] != next else { return }
        entries[index] = next
        persist()
    }

    /// Stops using `itemId` as an overlay.
    func remove(itemId: String) {
        let before = entries.count
        entries.removeAll { $0.itemId == itemId }
        guard entries.count != before else { return }
        persist()
    }

    // MARK: - Persistence

    private func load() {
        guard let data = defaults.data(forKey: key) else { return }
        do {
            entries = try JSONDecoder().decode([MediaOverlayEntry].self, from: data)
        } catch {
            logger.error("Failed to decode media overlays: \(error.localizedDescription)")
        }
    }

    private func persist() {
        do {
            defaults.set(try JSONEncoder().encode(entries), forKey: key)
        } catch {
            logger.error("Failed to encode media overlays: \(error.localizedDescription)")
        }
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self)
    }
}
