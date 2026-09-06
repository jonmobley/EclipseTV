//
//  LibraryGridViewController+ShowPreview.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Show Preview Gallery

extension LibraryGridViewController {

    /// Opens the Show swipe gallery starting at `id` (still, Screensaver, or Background).
    ///
    /// - Returns: `true` when Preview was presented.
    @discardableResult
    func presentShowPreviewGallery(startingAt id: String) -> Bool {
        guard !isPreviewAlreadyOpen else { return true }
        let pages = ShowPreviewGallery.items(from: openShowGridItems)
        guard let index = pages.firstIndex(where: { $0.id == id }) else { return false }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let preview = ShowPreviewViewController(items: pages, startIndex: index)
        preview.onDismiss = { [weak self] id in
            self?.revealShowMember(id: id)
        }
        preview.optionsMenuProvider = { [weak self] context in
            self?.previewOptionsMenu(context)
        }
        present(preview, animated: true)
        return true
    }

    /// True when any phone Preview is already on screen.
    var isPreviewAlreadyOpen: Bool {
        isAlreadyOpen(ShowPreviewViewController.self)
            || isAlreadyOpen(LocalMediaPreviewViewController.self)
            || isAlreadyOpen(DisplayModeMediaPreviewViewController.self)
            || isAlreadyOpen(LocalVideoPreviewViewController.self)
    }
}
