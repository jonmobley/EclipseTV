//
//  ShowSelectSlideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// Eligibility for "Create Slideshow" from Show multi-select.
enum ShowSelectSlideshow {

    /// Image ids for a new slideshow, in grid order.
    ///
    /// `nil` unless every selected tile is a still image. Videos, tools, websites,
    /// and PDFs hide Create Slideshow — playback is stills-only.
    static func imageIds(
        selectedIds: Set<String>,
        items: [ShowGridItem]
    ) -> [String]? {
        guard !selectedIds.isEmpty else { return nil }
        var images: [String] = []
        var matched = Set<String>()
        for item in items {
            guard let id = item.selectionId, selectedIds.contains(id) else { continue }
            guard case .media(let media) = item, !media.isVideo else { return nil }
            matched.insert(id)
            images.append(id)
        }
        guard matched == selectedIds, !images.isEmpty else { return nil }
        return images
    }
}
