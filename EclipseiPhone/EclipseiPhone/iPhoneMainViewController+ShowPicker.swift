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

    /// How many Shows the dropdown lists inline before the rest fall to "Open Show".
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

    /// "Open Show" submenu for the header dropdown, or `nil` when nothing is openable.
    ///
    /// Nested rather than inline so the top level stays a short list of verbs. Callers
    /// should only exclude the currently open Show — never the Recent list — so this
    /// entry stays discoverable even when every Show already fits inline.
    /// - Parameter excludedIds: Shows to leave out, e.g. the one already open.
    func openShowSubmenu(excluding excludedIds: Set<UUID>) -> UIMenu? {
        let groups = showMenuGroups(excluding: excludedIds)
        guard !groups.isEmpty else { return nil }
        return UIMenu(
            title: "Open Show",
            image: UIImage(systemName: "rectangle.stack"),
            children: groups
        )
    }

    /// Menu rows for opening a Show: active Display Mode first, then the other mode.
    /// - Parameter excludedIds: Shows to leave out, e.g. the open one and the recents.
    func showMenuGroups(excluding excludedIds: Set<UUID>) -> [UIMenuElement] {
        let active = ExternalOutputSettings.orientation
        let shows = LocalAlbumStore.shared.albums.filter { !excludedIds.contains($0.id) }
        let groups: [(ExternalOutputOrientation, [LocalAlbum])] = [
            (active, shows.filter { $0.orientation == active }),
            (
                active == .landscape ? .portrait : .landscape,
                shows.filter { $0.orientation != active }
            )
        ]
        return groups.compactMap { mode, group in
            guard !group.isEmpty else { return nil }
            return UIMenu(
                title: mode.rawValue,
                options: .displayInline,
                children: group.map { openShowAction(for: $0) }
            )
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
    ///
    /// The mode switch is applied before opening so the Show grid resolves its media
    /// against the matching library bucket instead of the mode being left behind.
    private func openShowFromPicker(id: UUID) {
        guard let show = LocalAlbumStore.shared.album(id: id) else { return }
        if show.orientation != ExternalOutputSettings.orientation {
            ExternalOutputSettings.orientation = show.orientation
            libraryViewController.applyLayoutMode()
        }
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

    /// Home tile caption: prefixes Landscape/Vertical when the Show is in the other mode.
    var homeRecentSubtitle: String {
        let relative = lastOpenedSubtitle
        guard orientation != ExternalOutputSettings.orientation else { return relative }
        return "\(orientation.rawValue) · \(relative)"
    }
}
