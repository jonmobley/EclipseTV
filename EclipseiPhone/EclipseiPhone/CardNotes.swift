//
//  CardNotes.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Which cards can carry a note

extension ShowGridItem {

    /// Key in `MediaNoteStore` for this card's presenter note, or nil for cards
    /// where a note makes no sense.
    ///
    /// Photos and videos use their library id (that is what iCloud carries to the
    /// Mac). Every other card kind uses its own id, so the note follows the card
    /// from Show to Show. Camera, Background, Screensaver, PTZ and Camera Presets
    /// are global tools shared by every Show, so a note on one would appear in
    /// all of them; they get none. `unresolved` and `add` are not real cards.
    var noteId: String? {
        switch self {
        case .media(let media): return media.id
        case .website(let page): return page.id.uuidString
        case .pdf(let doc): return doc.id.uuidString
        case .slideshow(let show): return show.id.uuidString
        case .countdown(let item): return item.id.uuidString
        case .livePoll(let item): return item.id.uuidString
        case .prompter(_, let scriptId): return scriptId.uuidString
        case .screensaver, .logo, .camera, .cameraPreset, .ptzCamera, .unresolved, .add:
            return nil
        }
    }
}

extension ShowProgram {

    /// Note key for whatever is live, matching `ShowGridItem.noteId`.
    var noteId: String? {
        switch kind {
        case .media, .web, .pdf, .slideshow, .countdown, .livePoll, .prompter:
            return itemId
        case .camera, .ptzCamera, .logo, .screensaver, .black:
            return nil
        }
    }
}

// MARK: - Menu action

extension LibraryGridViewController {

    /// Add note / Edit note for any card, keyed by `ShowGridItem.noteId`.
    func cardNoteAction(forId id: String) -> UIAction {
        UIAction(
            title: MediaNoteStore.menuTitle(forId: id),
            image: UIImage(systemName: "note.text")
        ) { [weak self] _ in
            self?.presentNoteComposer(forId: id)
        }
    }
}
