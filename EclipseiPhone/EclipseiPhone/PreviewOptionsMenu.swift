//
//  PreviewOptionsMenu.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// What a host needs to build the ⋯ menu for the fullscreen Preview header.
///
/// Preview borrows the tile menu from whichever screen opened it, so the actions
/// match the ⋯ the user came from instead of drifting into a fourth variant.
struct PreviewMenuContext {

    /// Library item currently on screen.
    let itemId: String

    /// Preview itself. Anything modal must present from here — the screen that
    /// built this menu is covered by Preview, so UIKit drops a present from there.
    weak var presenter: UIViewController?

    /// Runs `action` once Preview is off screen.
    ///
    /// Required for anything that deletes the item or replaces its file: the swipe
    /// galleries snapshot their pages at init, so mutating in place would leave a
    /// stale image on screen and an index pointing at media that no longer exists.
    let afterClosing: (@escaping () -> Void) -> Void
}

extension UIViewController {

    /// Builds a context that presents from, and dismisses, this Preview.
    func previewMenuContext(itemId: String) -> PreviewMenuContext {
        PreviewMenuContext(itemId: itemId, presenter: self) { [weak self] action in
            guard let self else { return }
            self.dismiss(animated: true, completion: action)
        }
    }

    /// Slide-up note composer for a still, presented from whatever is on top.
    func presentMediaNoteComposer(forId id: String) {
        present(MediaNoteComposerViewController.makeNavigation(itemId: id), animated: true)
    }
}
