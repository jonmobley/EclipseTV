//
//  AppSearch.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: The header's search covers the whole app, whatever page it is
//               opened from (owner's call 2026-11-26): Shows, the open Show's
//               cards, the Library and Music. Pure rules here; the results list is
//               `AppSearchResultsView`, the wiring `iPhoneMainViewController+AppSearch`.
//

import Foundation

/// A group of results, in the order the list shows them.
enum AppSearchSection: Int, CaseIterable {
    case shows
    case thisShow
    case library
    case music

    var title: String {
        switch self {
        case .shows: return "Shows"
        case .thisShow: return "This Show"
        case .library: return "Library"
        case .music: return "Music"
        }
    }
}

/// Where tapping a result goes.
enum AppSearchTarget: Equatable {
    /// Opens this Show.
    case show(UUID)
    /// Goes to this page with the search applied there, so the match is on screen.
    case page(HomeTab)
}

/// One row of the results list.
struct AppSearchResult: Equatable {
    let section: AppSearchSection
    let title: String
    let symbolName: String
    let target: AppSearchTarget
}

/// Something that can be found: its name and the icon it shows with.
struct AppSearchEntry: Equatable {
    let title: String
    /// Extra words it is also found by (a file name, a website's address).
    var keywords: [String] = []
    let symbolName: String
}

/// Everything search looks through, gathered from the stores.
struct AppSearchCatalog {
    var shows: [(id: UUID, entry: AppSearchEntry)] = []
    var thisShow: [AppSearchEntry] = []
    var library: [AppSearchEntry] = []
    var music: [AppSearchEntry] = []
}

enum AppSearch {

    /// Rows kept per section, so a short query never builds an endless list.
    static let maxResultsPerSection = 25

    /// Results for `query`, grouped by section; empty sections are left out.
    static func results(
        for query: String,
        in catalog: AppSearchCatalog
    ) -> [(section: AppSearchSection, results: [AppSearchResult])] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }

        func matching(
            _ entries: [AppSearchEntry],
            section: AppSearchSection,
            target: (Int) -> AppSearchTarget
        ) -> [AppSearchResult] {
            var found: [AppSearchResult] = []
            for (index, entry) in entries.enumerated()
            where LibrarySearch.matches(needle, in: [entry.title] + entry.keywords) {
                found.append(AppSearchResult(
                    section: section,
                    title: entry.title,
                    symbolName: entry.symbolName,
                    target: target(index)
                ))
                if found.count == maxResultsPerSection { break }
            }
            return found
        }

        let groups: [(AppSearchSection, [AppSearchResult])] = [
            (.shows, matching(catalog.shows.map(\.entry), section: .shows) {
                .show(catalog.shows[$0].id)
            }),
            (.thisShow, matching(catalog.thisShow, section: .thisShow) { _ in .page(.show) }),
            (.library, matching(catalog.library, section: .library) { _ in .page(.library) }),
            (.music, matching(catalog.music, section: .music) { _ in .page(.music) }),
        ]
        return groups.compactMap { group in
            group.1.isEmpty ? nil : (section: group.0, results: group.1)
        }
    }
}

// MARK: - Show Cards

extension ShowGridItem {

    /// Icon a Show card has in the search results.
    var searchSymbolName: String {
        let icon: ThumbnailTypeIcon
        switch self {
        case .slideshow: icon = .slideshow
        case .livePoll: icon = .livePoll
        case .screensaver, .logo: icon = .photo
        case .camera, .cameraPreset: icon = .camera
        case .ptzCamera: icon = .ptzCamera
        case .countdown: icon = .countdown
        case .prompter: icon = .prompter
        case .template: icon = .template
        case .media(let media): icon = .media(isVideo: media.isVideo)
        case .website: icon = .website
        case .pdf: icon = .pdf
        case .unresolved, .add: icon = .photo
        }
        return icon.systemName
    }
}
