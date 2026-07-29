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

    /// "Open Show" submenu for the Eclipse dropdown, or `nil` when nothing is openable.
    ///
    /// Nested rather than inline so the top level stays a short list of verbs.
    /// - Parameter excludedId: Show to leave out, e.g. the one already open.
    func openShowSubmenu(excluding excludedId: UUID? = nil) -> UIMenu? {
        let groups = showMenuGroups(excluding: excludedId)
        guard !groups.isEmpty else { return nil }
        return UIMenu(
            title: "Open Show",
            image: UIImage(systemName: "rectangle.stack"),
            children: groups
        )
    }

    /// Menu rows for opening a Show: active Display Mode first, then the other mode.
    /// - Parameter excludedId: Show to leave out, e.g. the one already open.
    func showMenuGroups(excluding excludedId: UUID? = nil) -> [UIMenuElement] {
        let active = ExternalOutputSettings.orientation
        let shows = LocalAlbumStore.shared.albums.filter { $0.id != excludedId }
        let groups = [
            shows.filter { $0.orientation == active },
            shows.filter { $0.orientation != active }
        ]
        return groups.compactMap { group in
            guard !group.isEmpty else { return nil }
            return UIMenu(
                title: "",
                options: .displayInline,
                children: group.map { openShowAction(for: $0) }
            )
        }
    }

    private func openShowAction(for show: LocalAlbum) -> UIAction {
        UIAction(
            title: show.name,
            subtitle: show.showPickerModeBadge,
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

    /// Display Mode badge for a Show row, or `nil` when the row needs no marker.
    ///
    /// Vertical Shows are always badged. Landscape Shows are badged only while Vertical
    /// mode is active, where an unbadged row would be the ambiguous one.
    var showPickerModeBadge: String? {
        guard orientation == .portrait || ExternalOutputSettings.isVerticalMode else {
            return nil
        }
        return orientation.rawValue
    }

    /// Action-sheet row title with the mode inline, since sheets can't show icons.
    var showPickerSheetTitle: String {
        guard let badge = showPickerModeBadge else { return name }
        return "\(name) (\(badge))"
    }
}
