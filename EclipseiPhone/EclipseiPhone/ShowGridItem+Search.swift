//
//  ShowGridItem+Search.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import Foundation

extension ShowGridItem {

    /// The name a card is found by when searching a Show: its title, or what the
    /// tile is called (Camera, Background).
    var searchTitle: String? {
        switch self {
        case .slideshow(let slideshow): return slideshow.name
        case .livePoll(let poll): return poll.tileTitle()
        case .screensaver: return "Screensaver"
        case .logo: return "Background"
        case .camera: return "Camera"
        // The frame's own name is added by the grid (`matchesShowSearch`).
        case .cameraPreset: return "Camera Preset"
        case .ptzCamera: return "PTZ Camera"
        case .countdown(let countdown): return countdown.tileTitle()
        case .prompter: return "Prompter"
        case .template(let card): return card.name
        case .media(let media): return MediaTitleStore.displayTitle(for: media)
        case .website(let page):
            return page.title + " " + (page.url.host ?? page.url.absoluteString)
        case .pdf(let document): return document.title
        case .unresolved, .add: return nil
        }
    }

    /// Whether this card matches `query` (any case, accents ignored).
    func matchesSearch(_ query: String, extraName: String? = nil) -> Bool {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return true }
        guard var title = searchTitle else { return false }
        if let extraName { title += " " + extraName }
        return title.range(
            of: needle, options: [.caseInsensitive, .diacriticInsensitive]
        ) != nil
    }
}

extension LibraryGridViewController {

    /// Whether `item` matches the Show search; a Camera Preset also by its frame's name.
    func matchesShowSearch(_ item: ShowGridItem) -> Bool {
        var frameName: String?
        if case .cameraPreset(let frameId) = item {
            frameName = CameraFrameStore.shared.displayName(for: frameId)
        }
        return item.matchesSearch(showSearchQuery, extraName: frameName)
    }

    /// Filters the open Show's cards by `query`; empty shows them all again.
    func setShowSearchQuery(_ query: String) {
        guard query != showSearchQuery else { return }
        let wasSearching = isSearchingShow
        showSearchQuery = query
        guard isShowMode, wasSearching || isSearchingShow else { return }
        reloadLibraryGrid()
    }
}
