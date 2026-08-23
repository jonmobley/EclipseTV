//
//  LibraryGridViewController+SelectSlideshow.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Select → Create Slideshow

extension LibraryGridViewController {

    /// Actions-menu row when every selected tile is a still image.
    func createSlideshowAction() -> UIAction? {
        guard slideshowImageIdsFromSelection() != nil else { return nil }
        return UIAction(
            title: "Create Slideshow",
            image: UIImage(systemName: "rectangle.stack.badge.play")
        ) { [weak self] _ in
            DispatchQueue.main.async { self?.promptCreateSlideshowFromSelection() }
        }
    }

    /// Names the slideshow, then creates it from the selected stills.
    func promptCreateSlideshowFromSelection() {
        guard isSelecting, let showId = openShowId,
              let itemIds = slideshowImageIdsFromSelection() else { return }
        let alert = UIAlertController(
            title: "New Slideshow", message: nil, preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Slideshow name"
            field.autocapitalizationType = .words
            UserDisplayName.configureTextField(field)
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self] _ in
            let name = alert.textFields?.first?.text ?? ""
            self?.createSlideshowFromSelection(
                name: name, itemIds: itemIds, showId: showId
            )
        })
        present(alert, animated: true)
    }

    // MARK: - Private

    private func slideshowImageIdsFromSelection() -> [String]? {
        ShowSelectSlideshow.imageIds(
            selectedIds: selectedShowItemIds,
            items: openShowGridItems
        )
    }

    private func createSlideshowFromSelection(
        name: String,
        itemIds: [String],
        showId: UUID
    ) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showPresentationToast(SlideshowStore.StoreError.emptyName.localizedDescription)
            return
        }
        let orientation = LocalAlbumStore.shared.album(id: showId)?.orientation
            ?? ExternalOutputSettings.orientation
        do {
            _ = try SlideshowStore.shared.create(
                name: trimmed,
                showId: showId,
                itemIds: itemIds,
                orientation: orientation
            )
            endSelectMode()
            showPresentationToast("Slideshow created")
            UINotificationFeedbackGenerator().notificationOccurred(.success)
        } catch {
            showPresentationToast(error.localizedDescription)
        }
    }
}
