//
//  MediaLibraryPickerViewController+Menus.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Tile ⋯ Menus

extension MediaLibraryPickerViewController {

    /// Long-press menu for a library tile. Hidden while adding to a Show.
    func libraryContextMenu(for item: Item) -> UIMenu? {
        guard !isAddToShowMode else { return nil }
        switch item {
        case .media(let id):
            guard let libraryItem = TVLibraryStore.shared.items.first(where: { $0.id == id })
            else { return nil }
            return mediaLibraryMenu(for: libraryItem)
        case .pdf(let id):
            guard let doc = PDFStore.shared.documents.first(where: { $0.id == id }) else {
                return nil
            }
            return pdfLibraryMenu(for: doc)
        }
    }

    /// Preview, title, notes / video options, Edit, Add to Show, Delete.
    func mediaLibraryMenu(for item: LibraryItemDTO) -> UIMenu {
        if item.isAvailable == false {
            return unavailableMediaMenu(for: item)
        }
        var children: [UIMenuElement] = [
            previewAction { [weak self] in self?.previewMedia(item) },
            titleAction(forId: item.id)
        ]
        if item.isVideo {
            children.append(contentsOf: videoLibraryActions(for: item))
        } else {
            children.append(noteAction(forId: item.id))
        }
        children.append(editAction(forId: item.id))
        children.append(addToShowMenu(membershipId: item.id))
        children.append(deleteMediaAction(item))
        return UIMenu(children: children)
    }

    /// Preview, Add to Show, Delete. Library is the only place orphan PDFs can go.
    func pdfLibraryMenu(for doc: SavedPDF) -> UIMenu {
        UIMenu(children: [
            previewAction { [weak self] in self?.previewPDF(doc) },
            addToShowMenu(membershipId: doc.id.uuidString),
            deletePDFAction(doc)
        ])
    }

    private func unavailableMediaMenu(for item: LibraryItemDTO) -> UIMenu {
        UIMenu(children: [
            UIAction(
                title: "Re-send from Photos",
                image: UIImage(systemName: "arrow.up.circle")
            ) { [weak self] _ in
                self?.onRequestResend?(item.id)
            },
            deleteMediaAction(item)
        ])
    }
}

// MARK: - Actions

extension MediaLibraryPickerViewController {

    private func previewAction(handler: @escaping () -> Void) -> UIAction {
        UIAction(title: "Preview", image: UIImage(systemName: "eye")) { _ in
            handler()
        }
    }

    private func titleAction(forId id: String) -> UIAction {
        UIAction(
            title: MediaTitleStore.menuTitle(forId: id),
            image: UIImage(systemName: "textformat")
        ) { [weak self] _ in
            self?.presentMediaTitlePrompt(forId: id)
        }
    }

    private func noteAction(forId id: String) -> UIAction {
        UIAction(
            title: MediaNoteStore.menuTitle(forId: id),
            image: UIImage(systemName: "note.text")
        ) { [weak self] _ in
            let nav = MediaNoteComposerViewController.makeNavigation(itemId: id)
            self?.present(nav, animated: true)
        }
    }

    private func editAction(forId id: String) -> UIAction {
        UIAction(
            title: "Edit",
            image: UIImage(systemName: "crop")
        ) { [weak self] _ in
            self?.onRequestEdit?(id)
        }
    }

    private func videoLibraryActions(for item: LibraryItemDTO) -> [UIMenuElement] {
        guard item.isVideo, item.isAvailable != false else { return [] }
        let loopOn = item.isLooping ?? false
        let muted = item.isMuted ?? false
        var actions: [UIMenuElement] = [
            UIAction(
                title: "Loop",
                image: UIImage(systemName: loopOn ? "checkmark" : "repeat")
            ) { [weak self] _ in
                self?.onApplyVideoSetting?(item.id, !loopOn, nil)
                self?.reload()
            },
            UIAction(
                title: "Mute",
                image: UIImage(systemName: muted ? "checkmark" : "speaker.wave.2.fill")
            ) { [weak self] _ in
                self?.onApplyVideoSetting?(item.id, nil, !muted)
                self?.reload()
            }
        ]
        if LocalMediaStore.shared.localURL(forId: item.id) != nil {
            actions.append(UIAction(
                title: "Choose Thumbnail…",
                image: UIImage(systemName: "photo.on.rectangle")
            ) { [weak self] _ in
                self?.onRequestVideoThumbnail?(item.id)
            })
        }
        return actions
    }

    private func addToShowMenu(membershipId: String) -> UIMenuElement {
        let groups = ShowCopyDestinations.grouped(
            albums: LocalAlbumStore.shared.albums,
            activeOrientation: ExternalOutputSettings.orientation
        )
        guard !groups.isEmpty else {
            return UIAction(
                title: "Add to Show",
                subtitle: "No Shows",
                image: UIImage(systemName: "folder.badge.plus"),
                attributes: .disabled
            ) { _ in }
        }
        return UIMenu(
            title: "Add to Show",
            image: UIImage(systemName: "folder.badge.plus"),
            children: groups.map { group in
                UIMenu(
                    title: "",
                    options: .displayInline,
                    children: group.map { show in
                        self.addToShowAction(membershipId: membershipId, show: show)
                    }
                )
            }
        )
    }

    private func addToShowAction(membershipId: String, show: LocalAlbum) -> UIAction {
        UIAction(
            title: show.name,
            image: UIImage(systemName: show.showPickerIconName)
        ) { [weak self] _ in
            self?.addMembership(membershipId, to: show)
        }
    }

    private func addMembership(_ membershipId: String, to show: LocalAlbum) {
        let members = Set(show.itemIds)
        let finish = {
            LocalAlbumStore.shared.add(itemId: membershipId, toAlbumId: show.id)
        }
        if AlreadyInShowAlert.needsConfirmation(
            selectedIds: [membershipId],
            memberIds: members
        ) {
            AlreadyInShowAlert.present(from: self, onContinue: finish)
            return
        }
        finish()
    }
}

// MARK: - Delete

extension MediaLibraryPickerViewController {

    private func deleteMediaAction(_ item: LibraryItemDTO) -> UIAction {
        UIAction(
            title: "Delete",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeleteMedia(item)
        }
    }

    private func deletePDFAction(_ doc: SavedPDF) -> UIAction {
        UIAction(
            title: "Delete PDF",
            image: UIImage(systemName: "trash"),
            attributes: .destructive
        ) { [weak self] _ in
            self?.confirmDeletePDF(doc)
        }
    }

    private func confirmDeleteMedia(_ item: LibraryItemDTO) {
        let isPending = PendingUploadStore.shared.contains(id: item.id)
        let linked = onIsEclipseTVLinked?() ?? false
        if !isPending && !linked {
            presentNotConnectedAlert()
            return
        }
        let message = isPending
            ? "This removes the item you added."
            : "This removes the item from your Apple TV library."
        let alert = UIAlertController(
            title: "Delete?",
            message: message,
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { [weak self] _ in
            self?.onPerformDelete?(item.id)
            self?.reload()
        })
        present(alert, animated: true)
    }

    private func confirmDeletePDF(_ doc: SavedPDF) {
        let alert = UIAlertController(
            title: "Delete PDF?",
            message: "“\(doc.title)” is removed from every Show and from Library.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Delete", style: .destructive) { _ in
            let manager = ExternalDisplayManager.shared
            if manager.isPDFLive, manager.livePDFDocumentId == doc.id {
                manager.stopPDFAndRestoreLibrary()
            }
            PDFStore.shared.remove(id: doc.id)
        })
        present(alert, animated: true)
    }

    private func presentNotConnectedAlert() {
        let alert = UIAlertController(
            title: "EclipseTV Not Linked",
            message: "This action needs a link to the Eclipse TV app (pairing code). "
                + "AirPlay alone is enough to present, but not for this.",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Connect…", style: .default) { [weak self] _ in
            self?.onRequestEclipseTVConnect?()
        })
        present(alert, animated: true)
    }
}
