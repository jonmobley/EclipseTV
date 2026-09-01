//
//  ShowGridItem.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

/// One cell in an open Show's grid: tools, members, slideshows, and Live Poll
/// cards in `LocalAlbum.resolvedSurfaceIds` order. Empty Shows append a trailing Add tile.
enum ShowGridItem: Equatable {
    case slideshow(Slideshow)
    case livePoll(ShowLivePoll)
    case screensaver
    case logo
    case camera
    case countdown(ShowCountdown)
    case media(LibraryItemDTO)
    case website(WebPage)
    case pdf(SavedPDF)
    /// Membership id whose local store entry has not arrived yet (CloudKit lag).
    case unresolved(id: String)
    case add

    /// Library media id whose decoded thumb backs this tile, if any.
    var libraryThumbnailId: String? {
        switch self {
        case .media(let media): return media.id
        case .slideshow(let show): return show.resolvedCoverId
        default: return nil
        }
    }

    /// Multi-select id (nil for slideshow / Add).
    var selectionId: String? {
        switch self {
        case .screensaver: return ShowToolToken.screensaver
        case .logo: return ShowToolToken.logo
        case .camera: return ShowToolToken.camera
        case .livePoll(let item): return ShowLivePollToken.token(for: item.id)
        case .countdown(let item): return ShowCountdownToken.token(for: item.id)
        case .media(let media): return media.id
        case .website(let page): return page.id.uuidString
        case .pdf(let doc): return doc.id.uuidString
        case .unresolved(let id): return id
        case .slideshow, .add: return nil
        }
    }
}
