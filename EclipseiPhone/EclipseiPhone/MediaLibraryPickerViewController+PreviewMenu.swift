//
//  MediaLibraryPickerViewController+PreviewMenu.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Fullscreen Preview ⋯ Menu

extension MediaLibraryPickerViewController {

    /// ⋯ menu for the fullscreen Preview header.
    ///
    /// Mirrors `mediaLibraryMenu` without its own Preview entry. Prompts present
    /// from Preview rather than this picker, which Preview covers; Delete waits
    /// for it to close, since it invalidates the page on screen.
    ///
    /// Stills only — videos open the system player, which carries no header.
    func previewOptionsMenu(_ context: PreviewMenuContext) -> UIMenu? {
        guard let item = TVLibraryStore.shared.items.first(where: { $0.id == context.itemId }),
              !item.isVideo, item.isAvailable != false else { return nil }

        var children: [UIMenuElement] = [previewTitleAction(for: item, context)]
        if !MediaNoteStore.shouldShowOverlay(forId: item.id) {
            // The footer card already offers this whenever it is on screen.
            children.append(previewNoteAction(for: item, context))
        }
        children.append(screenFitMenu(for: item, closing: context))
        children.append(addToShowMenu(membershipId: item.id, presenter: context.presenter))
        children.append(previewDeleteAction(for: item, context))
        return UIMenu(children: children)
    }

    // MARK: - Private

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

    private func previewNoteAction(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> UIAction {
        UIAction(
            title: MediaNoteStore.menuTitle(forId: item.id),
            image: UIImage(systemName: "note.text")
        ) { _ in
            context.presenter?.presentMediaNoteComposer(forId: item.id)
        }
    }

    private func screenFitMenu(
        for item: LibraryItemDTO,
        closing context: PreviewMenuContext
    ) -> UIMenu {
        MediaFitMenu.make(
            forId: item.id,
            offersFitFill: MediaFitAvailability.fitDiffersFromFill(forId: item.id) ?? true,
            onSelectFit: { [weak self] mode in
                self?.onApplyScreenFit?(item, mode)
            },
            onCustom: { [weak self] in
                context.afterClosing {
                    self?.onRequestEdit?(item.id)
                }
            }
        )
    }

    private func previewDeleteAction(
        for item: LibraryItemDTO,
        _ context: PreviewMenuContext
    ) -> UIAction {
        UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            context.afterClosing {
                self?.confirmDeleteMedia(item)
            }
        }
    }
}
