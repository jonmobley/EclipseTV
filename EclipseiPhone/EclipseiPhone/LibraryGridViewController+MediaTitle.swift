//
//  LibraryGridViewController+MediaTitle.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Add / Edit Title

extension LibraryGridViewController {

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
        })
        present(alert, animated: true)
    }
}
