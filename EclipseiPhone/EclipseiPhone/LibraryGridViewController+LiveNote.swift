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
        guard QuestPollSessionStore.shared.practiceMembershipId == nil else {
            return nil
        }
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

    /// Tallest an expanded card gets in stacked chrome, as a share of the safe area.
    static let stackedLiveNoteMaxHeightFraction: CGFloat = 0.4

    /// Expanded card cap in stacked chrome. Above it the note scrolls inside the card.
    static func stackedLiveNoteMaxHeight(safeAreaHeight: CGFloat) -> CGFloat {
        (safeAreaHeight * stackedLiveNoteMaxHeightFraction).rounded(.down)
    }

    /// Expanded card cap beside the grid: whatever the leading column has left
    /// under a preview held at its collapsed-card height.
    ///
    /// An expanding note never shrinks the preview. It's on screen for the
    /// presenter to watch, and past this cap the note scrolls instead.
    /// - Parameters:
    ///   - columnHeight: Leading column height shared by the hero and the note.
    ///   - heroHeight: Hero height with the collapsed card.
    static func sideBySideLiveNoteMaxHeight(columnHeight: CGFloat, heroHeight: CGFloat) -> CGFloat {
        max(0, columnHeight - heroHeight)
    }

    /// True when a sync brings different content, which returns the card to collapsed.
    static func liveNoteContentChanged(
        fromId: String?, note fromNote: String?, toId: String?, note toNote: String?
    ) -> Bool {
        fromId != toId || fromNote != toNote
    }

    /// Reloads the card for whatever is live, relaying out when it changed.
    func syncLiveNoteChrome() {
        let id = liveNoteItemId
        let note = id.flatMap { MediaNoteStore.note(forId: $0) }
        let changed = Self.liveNoteContentChanged(
            fromId: presentedLiveNoteId, note: presentedLiveNote, toId: id, note: note
        )
        presentedLiveNoteId = id
        presentedLiveNote = note
        if let note {
            liveNoteCard.configure(note: note)
        }
        guard changed else { return }
        liveNoteCard.setExpanded(false)
        forceChromeLayout()
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
        return liveNoteCard.height(forWidth: width, maxHeight: liveNoteMaxHeight())
    }

    /// Expands or collapses the live note in place, moving the chrome with it.
    /// The grid moves too, so the card never draws over the preview.
    @objc func handleLiveNoteTap() {
        guard presentedLiveNoteId != nil, liveNoteCard.isToggleable else { return }
        liveNoteCard.setExpanded(!liveNoteCard.isExpanded)
        UIView.animate(
            withDuration: ExpandableNoteCardView.toggleDuration,
            delay: 0,
            options: [.curveEaseInOut, .beginFromCurrentState]
        ) {
            self.forceChromeLayout()
            self.view.layoutIfNeeded()
        } completion: { _ in
            self.liveNoteCard.flashScrollIndicators()
        }
    }

    /// Opens the composer for the live item's note.
    func handleLiveNoteEdit() {
        guard let id = presentedLiveNoteId else { return }
        presentMediaNoteComposer(forId: id, anchor: liveNoteCard.editAnchor)
    }

    /// Runs the guarded work in the chrome pass: both the landscape hero height
    /// and the grid's top inset are sized around the card.
    func forceChromeLayout() {
        lastLayoutWidth = 0
        lastLayoutHeight = 0
        updateChromeLayoutIfNeeded()
    }

    // MARK: - Private

    /// Tallest the card may get right now, from the view rather than the screen
    /// so Split View and Stage Manager resizes follow.
    private func liveNoteMaxHeight() -> CGFloat {
        if isSideBySideChrome {
            return sideBySideLiveNoteMaxHeight
        }
        let safe = view.safeAreaInsets
        return Self.stackedLiveNoteMaxHeight(
            safeAreaHeight: view.bounds.height - safe.top - safe.bottom
        )
    }

    /// The preview's width, however the hero is currently sized. Full-bleed
    /// portrait has no width constraint — it spans the page inside `headerInset`.
    private func liveNoteCardWidth() -> CGFloat {
        if let heroWidthConstraint, heroWidthConstraint.isActive {
            return heroWidthConstraint.constant
        }
        return max(0, view.bounds.width - headerInset * 2)
    }
}
