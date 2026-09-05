//
//  ThumbnailMemoryCache.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// In-memory thumbnail store keyed by library item id.
///
/// Follows the standard iOS two-level pattern:
/// - **`NSCache`** — purgeable under memory pressure (Apple’s intended behavior).
///   Cost is decoded bitmap bytes; both `totalCostLimit` and `countLimit` are set.
/// - **Visible pins** — strong refs only for ids currently on-screen. This is not a
///   second general-purpose cache; it is the “don’t blank what the user is looking
///   at” contract when go-live / video decode triggers an `NSCache` purge.
///
/// Disk persistence lives in `TVLibraryStore`. A cache miss must always be able to
/// rebuild from disk — never treat memory as source of truth.
///
/// Not thread-safe: call from a single actor (`TVLibraryStore` owns it on MainActor).
final class ThumbnailMemoryCache {

    private let cache = NSCache<NSString, UIImage>()

    /// Ids handed to the cache. `NSCache` can't be enumerated, and entries it evicts on
    /// its own just make a later `removeObject` a no-op.
    private var knownIds: Set<String> = []

    /// Strong refs for tiles currently on screen (typically a dozen, not the library).
    private var visiblePins: [String: UIImage] = [:]
    private var visibleIds: Set<String> = []

    /// - Parameters:
    ///   - megabyteLimit: Ceiling for the purgeable `NSCache` pool (decoded bytes).
    ///   - countLimit: Max entries in the purgeable pool (backstop beside cost).
    init(megabyteLimit: Int, countLimit: Int = 100) {
        cache.name = "Eclipse.LibraryThumbnails"
        cache.totalCostLimit = max(megabyteLimit, 1) * 1_024 * 1_024
        cache.countLimit = max(countLimit, 1)
    }

    /// Budget for grid thumbs: ~2% of RAM, clamped so video decode still has headroom.
    static func defaultMegabyteLimit() -> Int {
        let physicalMB = ProcessInfo.processInfo.physicalMemory / (1_024 * 1_024)
        let twoPercent = Int(physicalMB / 50)
        return min(max(twoPercent, 32), 96)
    }

    /// Reads or writes the thumbnail for `id`; assigning nil evicts it.
    subscript(id: String) -> UIImage? {
        get {
            if let pinned = visiblePins[id] { return pinned }
            return cache.object(forKey: id as NSString)
        }
        set {
            guard let newValue else {
                knownIds.remove(id)
                cache.removeObject(forKey: id as NSString)
                visiblePins.removeValue(forKey: id)
                return
            }
            knownIds.insert(id)
            cache.setObject(
                newValue,
                forKey: id as NSString,
                cost: Self.byteCount(of: newValue)
            )
            if visibleIds.contains(id) {
                visiblePins[id] = newValue
            }
        }
    }

    /// Pins one on-screen id without rebuilding the visible set.
    ///
    /// Used while the grid is scrolling so each `willDisplay` is O(1). Off-screen
    /// pins are trimmed when scrolling settles via `setVisibleIds(_:)`.
    func pinVisibleId(_ id: String) {
        visibleIds.insert(id)
        if visiblePins[id] == nil, let cached = cache.object(forKey: id as NSString) {
            visiblePins[id] = cached
        }
    }

    /// Pins currently visible tile ids so an `NSCache` purge can’t blank the grid.
    ///
    /// Keeps existing pins for ids that remain visible (even if `NSCache` already
    /// dropped them). Newly visible ids are promoted from `NSCache` when present;
    /// otherwise they pin when the next disk load / `set` arrives.
    func setVisibleIds(_ ids: Set<String>) {
        var nextPins: [String: UIImage] = [:]
        for id in ids {
            if let existing = visiblePins[id] {
                nextPins[id] = existing
            } else if let cached = cache.object(forKey: id as NSString) {
                nextPins[id] = cached
            }
        }
        visiblePins = nextPins
        visibleIds = ids
    }

    /// Drops thumbnails whose ids are no longer in the library.
    func retain(ids: Set<String>) {
        for id in knownIds.subtracting(ids) {
            self[id] = nil
        }
        // Visible set may still reference removed ids until the grid refreshes pins.
        if !visibleIds.isSubset(of: ids) {
            setVisibleIds(visibleIds.intersection(ids))
        }
    }

    /// Drops every cached thumbnail (library or Display Mode switch).
    func removeAll() {
        knownIds.removeAll()
        cache.removeAllObjects()
        visiblePins.removeAll()
        visibleIds.removeAll()
    }

    /// Decoded size in bytes (`bytesPerRow × height`), used as the cache cost.
    private static func byteCount(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
