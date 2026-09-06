//
//  LibraryGridViewController+PreviewMenu.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Fullscreen Preview ⋯ Menu

extension LibraryGridViewController {

    /// ⋯ menu for the fullscreen Preview header.
    ///
    /// Mirrors the tile menu minus the entries that mean nothing once the media is
    /// already fullscreen: Preview itself, plus Arrange and Select, which put the
    /// *grid* into a mode the user can't see from here.
    ///
    /// Stills only — videos open the system player, which carries no header.
    func previewOptionsMenu(_ context: PreviewMenuContext) -> UIMenu? {
        guard let item = store.items.first(where: { $0.id == context.itemId }),
              !item.isVideo, item.isAvailable != false else { return nil }

        var children: [UIMenuElement] = [previewTitleAction(for: item, context)]
        if let note = previewNoteAction(for: item, context) {
            children.append(note)
        }
        children.append(screenFitMenu(for: item))
        children.append(contentsOf: openShow.map { showMemberActions(for: item, in: $0, context) }
            ?? libraryActions(for: item, context))
        return UIMenu(children: children)
    }

    // MARK: - Private

    /// Add / Edit title. The header picks the new text up on the spot, since it
    /// watches `MediaTitleStore`.
    private func previewTitleAction(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> UIAction {
        UIAction(
            title: MediaTitleStore.menuTitle(forId: item.id),
            image: UIImage(systemName: "textformat")
        ) { _ in
            context.presenter?.presentMediaTitlePrompt(forId: item.id)
        }
    }

    /// Add note, but only when the footer card isn't already offering it.
    ///
    /// With the default `whenExists` visibility a note-less still shows no card, so
    /// the menu is the only way to write a first note from inside Preview. Once a
    /// card is on screen the user taps that instead of hunting through ⋯.
    private func previewNoteAction(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> UIAction? {
        guard !MediaNoteStore.shouldShowOverlay(forId: item.id) else { return nil }
        return UIAction(
            title: MediaNoteStore.menuTitle(forId: item.id),
            image: UIImage(systemName: "note.text")
        ) { _ in
            context.presenter?.presentMediaNoteComposer(forId: item.id)
        }
    }

    /// Opens the pan/zoom cropper so the user can re-frame the stored file.
    ///
    /// Sits beside Screen Fit because both decide what the audience sees, but this
    /// one rewrites the image instead of choosing Fit vs Fill at display time.
    /// Deferred until Preview is off screen — it replaces the file the page on
    /// screen was built from.
    private func previewEditAction(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> UIAction {
        UIAction(
            title: "Edit",
            image: UIImage(systemName: "crop")
        ) { [weak self] _ in
            context.afterClosing {
                self?.onRequestEdit?(item.id)
            }
        }
    }

    /// Edit, Set as Show Cover and Remove, for Preview opened from an open Show.
    private func showMemberActions(
        for item: LibraryItemDTO,
        in album: LocalAlbum,
        _ context: PreviewMenuContext
    ) -> [UIMenuElement] {
        let isCover = album.resolvedCoverId == item.id
        let cover = UIAction(
            title: isCover ? "Show Cover" : "Set as Show Cover",
            image: UIImage(systemName: isCover ? "star.fill" : "star"),
            attributes: isCover ? [.disabled] : []
        ) { [weak self] _ in
            guard let self, let id = self.openShowId else { return }
            LocalAlbumStore.shared.setCover(itemId: item.id, albumId: id)
        }
        let remove = UIAction(
            title: "Remove",
            image: UIImage(systemName: "folder.badge.minus"),
            attributes: .destructive
        ) { [weak self] _ in
            context.afterClosing {
                guard let self, let id = self.openShowId else { return }
                LocalAlbumStore.shared.remove(itemId: item.id, fromAlbumId: id)
            }
        }
        return [previewEditAction(for: item, context), cover, remove]
    }

    /// Edit and Delete, for Preview opened from the Home grid.
    private func libraryActions(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> [UIMenuElement] {
        let delete = UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            context.afterClosing {
                self?.confirmDelete(id: item.id, name: item.name)
            }
        }
        return [previewEditAction(for: item, context), delete]
    }
}
