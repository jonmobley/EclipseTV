//
//  LibraryGridViewController+MediaTitle.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Add / Edit Title

extension LibraryGridViewController {

    /// Repaints tiles after titles or Show / Hide Title choices change.
    @objc func reloadGridForTitleChange() {
        reloadGridIfSafe()
    }

    /// Add title / Edit title action for photo and video tiles.
    func titleAction(for item: LibraryItemDTO) -> UIAction {
        UIAction(
            title: MediaTitleStore.menuTitle(forId: item.id),
            image: UIImage(systemName: "textformat")
        ) { [weak self] _ in
            self?.presentMediaTitlePrompt(forId: item.id)
        }
    }
}

extension UIViewController {

    /// Alert to add or edit an overlay title. Blank Save clears the title.
    func presentMediaTitlePrompt(forId id: String) {
        let hasTitle = MediaTitleStore.hasTitle(forId: id)
        let alert = UIAlertController(
            title: hasTitle ? "Edit Title" : "Add Title",
            message: nil,
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Title"
            field.text = MediaTitleStore.title(forId: id)
            field.autocapitalizationType = .sentences
            field.clearButtonMode = .whileEditing
            field.returnKeyType = .done
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Save", style: .default) { [weak alert] _ in
            MediaTitleStore.setTitle(alert?.textFields?.first?.text, forId: id)
            // Naming an untitled card means wanting to see the name; an
            // explicit Hide Title stays as chosen.
            if !hasTitle, MediaTitleStore.hasTitle(forId: id),
               CardTitleVisibility.choice(forId: id) == nil {
                CardTitleVisibility.setShown(true, forId: id)
            }
            EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: id)
        })
        present(alert, animated: true)
    }
}

// MARK: - Show / Hide Title

extension ShowGridItem {

    /// Whether this tile shows its title (fixed-title tiles always do).
    var isTitleShown: Bool {
        guard let title = cardTitle else { return true }
        return CardTitleVisibility.isShown(forId: title.id, kind: title.kind)
    }

    /// Show Title / Hide Title for the tile's ⋯ menu. The choice syncs to the
    /// user's other devices and to collaborators on a shared Show.
    @MainActor
    func titleVisibilityAction() -> UIAction {
        let shown = isTitleShown
        return UIAction(
            title: shown ? "Hide Title" : "Show Title",
            image: UIImage(systemName: shown ? "captions.bubble" : "captions.bubble.fill")
        ) { _ in
            guard let title = cardTitle else { return }
            CardTitleVisibility.setShown(!shown, forId: title.id)
            scheduleCardTitleSave()
        }
    }

    /// Queues the iCloud save that carries this tile's title choice.
    @MainActor
    func scheduleCardTitleSave() {
        let backend = EclipseSyncController.shared.backend
        switch self {
        case .slideshow(let show): backend.scheduleSlideshowSave(id: show.id)
        case .livePoll(let poll): backend.scheduleLivePollSave(id: poll.id)
        case .countdown(let countdown): backend.scheduleCountdownSave(id: countdown.id)
        case .media(let media): backend.scheduleMediaPrefsSave(libraryId: media.id)
        case .website(let page): backend.scheduleWebPageSave(id: page.id)
        case .pdf(let doc): backend.schedulePDFSave(id: doc.id)
        case .screensaver, .logo, .camera, .ptzCamera, .unresolved, .add: break
        }
    }
}
