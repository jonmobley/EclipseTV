//
//  iPhoneMainViewController+ShowPicker.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Pickers

/// Show pickers list both Display Modes, so each row carries its own mode: a Vertical
/// Show is always marked, and a Landscape Show is marked while Vertical mode is active.
/// Opening a Show from the other mode switches Display Mode first.
extension iPhoneMainViewController {

    /// How many Shows the dropdown lists inline as Recent Shows.
    private static let recentShowMenuLimit = 5

    /// The Shows the dropdown offers inline, most recently opened first.
    ///
    /// Recency is `LocalAlbumStore`'s own order — opening a Show moves it to the front —
    /// so these match the Home ribbon Show mode covers up. Both Display Modes are listed
    /// (glyph marks Landscape vs Vertical); opening an other-mode Show switches mode.
    /// - Parameter excludedId: Show to leave out, e.g. the one already open.
    func recentShowsForMenu(excluding excludedId: UUID? = nil) -> [LocalAlbum] {
        Array(
            LocalAlbumStore.shared.albums
                .filter { $0.id != excludedId }
                .prefix(Self.recentShowMenuLimit)
        )
    }

    /// Inline Recent Shows section for the header dropdown (both Display Modes).
    func recentShowsMenu(_ shows: [LocalAlbum]) -> UIMenu {
        UIMenu(
            title: "Recent Shows",
            options: .displayInline,
            children: shows.map { openShowAction(for: $0) }
        )
    }

    /// "Open Show" in the header dropdown — same Shows list as Home See All.
    /// `nil` when there are no Shows to open.
    func openShowListAction() -> UIAction? {
        guard !LocalAlbumStore.shared.albums.isEmpty else { return nil }
        return UIAction(
            title: "Open Show",
            image: UIImage(systemName: "rectangle.stack")
        ) { [weak self] _ in
            self?.libraryViewController.presentAllShows()
        }
    }

    private func openShowAction(for show: LocalAlbum) -> UIAction {
        // Mode is the glyph only (tall stack vs wide) — no Vertical/Landscape copy.
        UIAction(
            title: show.name,
            image: UIImage(systemName: show.showPickerIconName)
        ) { [weak self] _ in
            self?.openShowFromPicker(id: show.id)
        }
    }

    /// Opens `id`, switching Display Mode first when the Show lives in the other mode.
    private func openShowFromPicker(id: UUID) {
        libraryViewController.openLocalAlbum(id: id)
    }
}

// MARK: - Show Row Presentation

extension LocalAlbum {

    /// Row glyph: stacked tall cards for a Vertical Show, wide cards for Landscape.
    var showPickerIconName: String {
        orientation == .portrait
            ? "rectangle.portrait.on.rectangle.portrait"
            : "rectangle.stack"
    }

    /// Home tile caption: last-opened time only (no Landscape/Vertical prefix).
    var homeRecentSubtitle: String {
        lastOpenedSubtitle
    }

    /// Show list recency (See All). Format is the leading glyph only.
    var showListSubtitle: String {
        lastOpenedSubtitle
    }
}
