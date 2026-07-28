//
//  ShowGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One cell in an open Show's media grid (slideshows, photos/videos, or Add).
enum ShowGridItem: Equatable {
    case slideshow(Slideshow)
    case media(LibraryItemDTO)
    case add
}
