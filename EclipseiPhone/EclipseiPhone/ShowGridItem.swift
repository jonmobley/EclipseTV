//
//  ShowGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One cell in an open Show's grid: pinned slideshows, then tools and members
/// in `LocalAlbum.resolvedSurfaceIds` order. Empty Shows append a trailing Add tile.
enum ShowGridItem: Equatable {
    case slideshow(Slideshow)
    case screensaver
    case logo
    case camera
    case media(LibraryItemDTO)
    case website(WebPage)
    case pdf(SavedPDF)
    case add
}
