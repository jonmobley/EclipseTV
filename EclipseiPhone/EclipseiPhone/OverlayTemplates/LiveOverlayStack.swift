//
//  LiveOverlayStack.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Pure rules for which layered overlays are on output and in
//               what order they draw (the Mac's overlay stack, simplified).
//  Thread Safety: Value types - no shared mutable state.
//

import Foundation

// MARK: - LiveOverlayID

/// Identifies one layered overlay that can sit on top of the live picture.
enum LiveOverlayID: Hashable {
    /// A Show template card (`ShowTemplateCard.id`).
    case template(UUID)
    /// A photo or video used as an overlay (`MediaOverlayEntry.itemId`).
    case media(String)

    /// Stable text used to break draw-order ties the same way every time.
    var sortKey: String {
        switch self {
        case .template(let id): return "t:" + id.uuidString
        case .media(let id): return "m:" + id
        }
    }
}

// MARK: - LiveOverlayStack

/// The set of overlays currently on output.
///
/// Matches the Mac: tapping an overlay puts it on top of whatever is live
/// without replacing it; tapping a live overlay takes it off; several can be
/// on at once. Turning one on does not change the draw order; the persistent
/// `stackOrder` does (higher draws on top).
struct LiveOverlayStack: Equatable {

    // MARK: - Properties

    /// Overlays on output, in the order they were turned on.
    private(set) var liveIds: [LiveOverlayID] = []

    // MARK: - Queries

    /// Whether `id` is on output.
    func contains(_ id: LiveOverlayID) -> Bool {
        liveIds.contains(id)
    }

    /// Whether nothing is layered over the live picture.
    var isEmpty: Bool { liveIds.isEmpty }

    // MARK: - Mutations

    /// Turns `id` on when off, off when on.
    ///
    /// - Parameter id: The overlay the operator tapped.
    /// - Returns: Whether the overlay is on output afterwards.
    @discardableResult
    mutating func toggle(_ id: LiveOverlayID) -> Bool {
        if let index = liveIds.firstIndex(of: id) {
            liveIds.remove(at: index)
            return false
        }
        liveIds.append(id)
        return true
    }

    /// Takes `id` off output (no-op when it is not on).
    mutating func remove(_ id: LiveOverlayID) {
        liveIds.removeAll { $0 == id }
    }

    /// Takes every overlay off output.
    mutating func removeAll() {
        liveIds.removeAll()
    }

    /// Drops overlays whose card or media no longer exists.
    ///
    /// - Parameter exists: Whether the overlay's backing card/media is still around.
    mutating func prune(keeping exists: (LiveOverlayID) -> Bool) {
        liveIds.removeAll { !exists($0) }
    }

    // MARK: - Draw Order

    /// Bottom-to-top draw order for the live overlays.
    ///
    /// - Parameter stackOrder: The persistent stack order of each overlay
    ///   (nil when it can no longer be resolved; those are skipped).
    /// - Returns: Live overlays sorted bottom first; ties break on `sortKey`.
    func drawOrder(stackOrder: (LiveOverlayID) -> Int?) -> [LiveOverlayID] {
        liveIds
            .compactMap { id in stackOrder(id).map { (id, $0) } }
            .sorted { lhs, rhs in
                lhs.1 != rhs.1 ? lhs.1 < rhs.1 : lhs.0.sortKey < rhs.0.sortKey
            }
            .map(\.0)
    }
}
