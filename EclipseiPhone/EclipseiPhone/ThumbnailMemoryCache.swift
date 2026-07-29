//
//  ThumbnailMemoryCache.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Bounded in-memory thumbnail store, keyed by library item id.
///
/// Replaces an unbounded dictionary: decoded bitmaps are megabytes each, so a large
/// library could keep hundreds of megabytes resident and cause the memory pressure that
/// evicts everything else the app has warmed. `NSCache` also releases entries on system
/// memory warnings, which a dictionary never did.
///
/// Not thread-safe: call from a single actor (`TVLibraryStore` owns it on the main actor).
final class ThumbnailMemoryCache {

    private let cache = NSCache<NSString, UIImage>()

    /// Ids handed to the cache. `NSCache` can't be enumerated, and entries it evicts on
    /// its own just make a later `removeObject` a no-op.
    private var knownIds: Set<String> = []

    /// - Parameter megabyteLimit: Approximate ceiling for decoded pixel data.
    init(megabyteLimit: Int) {
        cache.totalCostLimit = megabyteLimit * 1_024 * 1_024
    }

    /// Reads or writes the thumbnail for `id`; assigning nil evicts it.
    subscript(id: String) -> UIImage? {
        get { cache.object(forKey: id as NSString) }
        set {
            guard let newValue else {
                knownIds.remove(id)
                cache.removeObject(forKey: id as NSString)
                return
            }
            knownIds.insert(id)
            cache.setObject(
                newValue,
                forKey: id as NSString,
                cost: Self.byteCount(of: newValue)
            )
        }
    }

    /// Drops thumbnails whose ids are no longer in the library.
    func retain(ids: Set<String>) {
        for id in knownIds.subtracting(ids) {
            self[id] = nil
        }
    }

    /// Drops every cached thumbnail (library or Display Mode switch).
    func removeAll() {
        knownIds.removeAll()
        cache.removeAllObjects()
    }

    /// Decoded size in bytes, used as the cache cost.
    private static func byteCount(of image: UIImage) -> Int {
        guard let cgImage = image.cgImage else { return 0 }
        return cgImage.bytesPerRow * cgImage.height
    }
}
