//
//  iPhoneMainViewController+AppSearch.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: The header's search, from any page, looks through the whole app
//               (Shows, the open Show's cards, Library, Music) and lists what it
//               finds. Tapping a Show opens it; tapping anything else goes to its
//               page with the search applied there, so the match is on screen.
//               Typing again brings the whole-app list back. See `AppSearch`.
//  Thread Safety: Main thread only - UIKit.
//

import UIKit

extension iPhoneMainViewController {

    /// Places the (hidden) results list under the header, down to the screen's
    /// bottom edge so it covers the Music button; its rows stop at the keyboard.
    func setupAppSearchResults() {
        let results = appSearchResultsView
        results.translatesAutoresizingMaskIntoConstraints = false
        results.isHidden = true
        results.onSelect = { [weak self] result in
            self?.selectAppSearchResult(result)
        }
        view.addSubview(results)
        NSLayoutConstraint.activate([
            results.topAnchor.constraint(equalTo: headerBar.bottomAnchor),
            results.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            results.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            results.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// Opens the header's search field, whichever page is in front.
    func beginPageSearch() {
        guard isHomeTabPaging, !headerBar.isSearching else { return }
        finishHomePagerSlide()
        searchingTab = nil
        // The field takes the tab row's place, so the header keeps its height.
        headerBar.beginSearch(placeholder: "Search Eclipse")
        refreshAppSearchResults()
    }

    /// The search text changed: back to the whole-app list for the new text.
    func applyPageSearch(_ text: String) {
        if searchingTab != nil {
            searchingTab = nil
            clearPageSearchFilters()
        }
        refreshAppSearchResults()
    }

    /// Closes the search field and shows every page whole again.
    ///
    /// Also runs when the page changes or the Show does: a filter left on a page
    /// nobody is looking at would hide cards with nothing on screen to say why.
    func endPageSearch(animated: Bool = true) {
        guard searchingTab != nil || headerBar.isSearching else { return }
        searchingTab = nil
        appSearchResultsView.isHidden = true
        clearPageSearchFilters()
        headerBar.endSearch()
    }

    // MARK: - Private

    private func clearPageSearchFilters() {
        libraryPagePicker?.setHomeTabSearchQuery("")
        libraryViewController.setShowSearchQuery("")
        audioLibraryViewController.searchQuery = ""
    }

    /// Lists what matches the typed text; nothing typed shows the page as it is.
    private func refreshAppSearchResults() {
        let query = headerBar.searchText
        let hasQuery = !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard headerBar.isSearching, searchingTab == nil, hasQuery else {
            appSearchResultsView.isHidden = true
            return
        }
        let catalog = appSearchCatalog()
        appSearchResultsView.thisShowName = catalog.thisShowName
        appSearchResultsView.show(AppSearch.results(for: query, in: catalog.catalog), query: query)
        if appSearchResultsView.isHidden {
            appSearchResultsView.isHidden = false
            // Above the Music player and camera button too: the list starts under
            // the header, so nothing of the header is covered, and every row stays
            // tappable once the keyboard is down.
            view.bringSubviewToFront(appSearchResultsView)
        }
    }

    private func selectAppSearchResult(_ result: AppSearchResult) {
        switch result.target {
        case .show(let id):
            endPageSearch()
            libraryViewController.openLocalAlbum(id: id)
            setHomeTab(.show, animated: true)
        case .page(let tab):
            let query = headerBar.searchText
            // The filtered list is each page's first screen; a playlist, album or
            // preview left open there would hide the match.
            switch tab {
            case .music: audioLibraryNavController?.popToRootViewController(animated: false)
            case .library: libraryPageNavController?.popToRootViewController(animated: false)
            case .home, .show: break
            }
            searchingTab = tab
            searchedShowId = libraryViewController.openShowId
            switch tab {
            case .library: libraryPagePicker?.setHomeTabSearchQuery(query)
            case .show: libraryViewController.setShowSearchQuery(query)
            case .music: audioLibraryViewController.searchQuery = query
            case .home: break
            }
            appSearchResultsView.isHidden = true
            headerBar.dismissSearchKeyboard()
            setHomeTab(tab, animated: true)
        }
    }

    /// Everything search can find right now.
    private func appSearchCatalog() -> (catalog: AppSearchCatalog, thisShowName: String?) {
        var catalog = AppSearchCatalog()
        catalog.shows = LocalAlbumStore.shared.albums.map { show in
            (id: show.id, entry: AppSearchEntry(title: show.name, symbolName: show.showPickerIconName))
        }

        var thisShowName: String?
        if let showId = libraryViewController.openShowId {
            thisShowName = LocalAlbumStore.shared.album(id: showId)?.name
            catalog.thisShow = libraryViewController.openShowGridItems.compactMap(Self.searchEntry)
        }

        let hidden = PendingDeletes.shared.hiddenLibraryIds
        let media = TVLibraryStore.shared.items.filter { !hidden.contains($0.id) }
        let pdfs = PDFStore.shared.documents.filter { !hidden.contains($0.id.uuidString) }
        catalog.library = media.map { item in
            AppSearchEntry(
                title: MediaTitleStore.displayTitle(for: item),
                keywords: [item.name],
                symbolName: ThumbnailTypeIcon.media(isVideo: item.isVideo).systemName
            )
        } + pdfs.map { pdf in
            AppSearchEntry(title: pdf.title, symbolName: ThumbnailTypeIcon.pdf.systemName)
        }

        catalog.music = AudioPlaylistStore.shared.playlists.map {
            AppSearchEntry(title: $0.name, symbolName: "music.note.list")
        } + AudioStore.shared.tracks.map {
            AppSearchEntry(title: $0.title, symbolName: "music.note")
        }
        return (catalog, thisShowName)
    }

    /// How an open Show's card is listed; found by the same words as the Show's
    /// own search (`ShowGridItem.searchTitle`, a preset's frame name).
    private static func searchEntry(for item: ShowGridItem) -> AppSearchEntry? {
        switch item {
        case .website(let page):
            let host = page.url.host ?? page.url.absoluteString
            return AppSearchEntry(
                title: page.title.isEmpty ? host : page.title,
                keywords: [host],
                symbolName: item.searchSymbolName
            )
        case .cameraPreset(let frameId):
            return AppSearchEntry(
                title: CameraFrameStore.shared.displayName(for: frameId),
                keywords: ["Camera Preset"],
                symbolName: item.searchSymbolName
            )
        default:
            guard let title = item.searchTitle else { return nil }
            return AppSearchEntry(title: title, symbolName: item.searchSymbolName)
        }
    }
}
