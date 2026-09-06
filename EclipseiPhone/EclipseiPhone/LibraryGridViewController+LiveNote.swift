//
//  LibraryGridViewController+LiveNote.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Docked Live Note

/// Note for whatever is live, docked under the preview — and under the slide
/// ribbon whenever that strip is up, since the ribbon owns the space directly
/// below the card.
extension LibraryGridViewController {

    /// Gap above the note card. A docked ribbon already carries
    /// `slideshowRibbonBottomPadding` inside its height, so the card only makes
    /// up the difference and the spacing reads the same either way.
    static func liveNoteTopGap(ribbonDocked: Bool) -> CGFloat {
        ribbonDocked
            ? max(0, sideBySideGutter - slideshowRibbonBottomPadding)
            : sideBySideGutter
    }

    /// Live still / video that actually carries a note. Overlays and tools own
    /// the hero themselves and have no library id to look a note up with.
    var liveNoteItemId: String? {
        guard showsLiveHero, !isLiveFromOtherShow else { return nil }
        guard !isBlackSelected, !isLogoSelected, !isScreensaverSelected else {
            return nil
        }
        guard livePollGateMembershipId == nil else { return nil }
        let manager = ExternalDisplayManager.shared
        guard !manager.isWebLive, !manager.isPDFLive, !manager.isCameraLive,
              !manager.isParkedOnQuickChangeStill, !manager.isCountdownLive else {
            return nil
        }
        guard let id = store.currentId, MediaNoteStore.hasNote(forId: id) else {
            return nil
        }
        return id
    }

    /// True while the note card is part of the live chrome.
    var showsLiveNote: Bool { showsLiveHero && presentedLiveNoteId != nil }

    /// Reloads the card for whatever is live, relaying out when it changed.
    func syncLiveNoteChrome() {
        let id = liveNoteItemId
        let note = id.flatMap { MediaNoteStore.note(forId: $0) }
        let changed = id != presentedLiveNoteId || note != presentedLiveNote
        presentedLiveNoteId = id
        presentedLiveNote = note
        if let note {
            liveNoteCard.configure(note: note)
        }
        guard changed else { return }
        // Both the landscape hero height and the grid's top inset are sized
        // around the card, so force the guarded work in the chrome pass to run.
        lastLayoutWidth = 0
        lastLayoutHeight = 0
        updateChromeLayoutIfNeeded()
    }

    /// Shows or hides the card and sizes it for the current preview width.
    func layoutLiveNoteCard() {
        let visible = showsLiveNote
        liveNoteCard.isHidden = !visible
        liveNoteCard.isUserInteractionEnabled = visible
        // Parked, the card collapses onto the ribbon's bottom edge so the black
        // plate and the grid inset land exactly where they did without it.
        liveNoteTopConstraint?.constant = visible
            ? Self.liveNoteTopGap(ribbonDocked: docksLiveSlideshowRibbon)
            : 0
        liveNoteHeightConstraint?.constant = visible ? measuredLiveNoteHeight() : 0
        guard visible else { return }
        view.bringSubviewToFront(liveNoteCard)
    }

    /// Card height for `width`, defaulting to the current preview width.
    func measuredLiveNoteHeight(width: CGFloat? = nil) -> CGFloat {
        guard showsLiveNote else { return 0 }
        let width = width ?? liveNoteCardWidth()
        guard width > 0 else { return 0 }
        return liveNoteCard.height(forWidth: width)
    }

    /// Opens the composer for the live item's note.
    @objc func handleLiveNoteTap() {
        guard let id = presentedLiveNoteId else { return }
        present(
            MediaNoteComposerViewController.makeNavigation(itemId: id),
            animated: true
        )
    }

    // MARK: - Private

    /// The preview's width, however the hero is currently sized. Full-bleed
    /// portrait has no width constraint — it spans the page inside `headerInset`.
    private func liveNoteCardWidth() -> CGFloat {
        if let heroWidthConstraint, heroWidthConstraint.isActive {
            return heroWidthConstraint.constant
        }
        return max(0, view.bounds.width - headerInset * 2)
    }
}
