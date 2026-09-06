//
//  LiveHeroBrowse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Resolves where a left/right swipe on the live hero should take live output:
/// the still `delta` steps from the live one, in the open Show's order.
///
/// Videos are skipped because the hero hands the horizontal axis to the transport
/// scrubber while one is live, and purged items are skipped because tapping those
/// opens the re-send sheet rather than going live. Both ends clamp instead of
/// wrapping — live output should not jump back to the top of the Show because the
/// operator swiped once too many times.
enum LiveHeroBrowse {

    /// Stills a hero swipe may land on, in Show order.
    static func browsableItems(in items: [LibraryItemDTO]) -> [LibraryItemDTO] {
        items.filter { !$0.isVideo && $0.isAvailable != false }
    }

    /// True when the live item is a browsable still with somewhere to swipe to.
    static func canBrowse(from currentId: String?, in items: [LibraryItemDTO]) -> Bool {
        guard let currentId else { return false }
        let browsable = browsableItems(in: items)
        guard browsable.count > 1 else { return false }
        return browsable.contains { $0.id == currentId }
    }

    /// The still `delta` steps from `currentId`.
    ///
    /// - Returns: `nil` at either end of the Show, and when the live item is not
    ///   itself a browsable still (a tool, overlay, or video owns live output).
    static func target(
        from currentId: String?,
        in items: [LibraryItemDTO],
        delta: Int
    ) -> LibraryItemDTO? {
        guard delta != 0, let currentId else { return nil }
        let browsable = browsableItems(in: items)
        guard let index = browsable.firstIndex(where: { $0.id == currentId }) else {
            return nil
        }
        let next = index + delta
        guard browsable.indices.contains(next) else { return nil }
        return browsable[next]
    }
}
