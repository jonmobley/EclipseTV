//
//  LibraryGridViewController+OverlayAdjust.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//
//  Description: Lets live overlays be dragged / pinched on the hero, and saves
//               where they end up. A template card's new placement goes to
//               iCloud with the card, so the Mac picks it up; photo / video
//               overlays stay on this phone, as before.
//  Thread Safety: Main actor only.
//

import UIKit

// MARK: - Overlay Adjust

extension LibraryGridViewController {

    /// Wires the hero's overlay drag / pinch to the overlay stores.
    func installHeroOverlayAdjust() {
        liveHeader.onAdjustOverlay = { [weak self] overlay, isFinal in
            self?.handleHeroOverlayAdjust(overlay, isFinal: isFinal)
        }
    }

    /// Whether a live overlay on the hero may be moved right now.
    ///
    /// Same rules as the hero's still / countdown adjust: only the open Show's own
    /// program, never a phone preview, while output is locked, during Blackout, or
    /// while following a director.
    var allowsHeroOverlayAdjust: Bool {
        showsLiveHero
            && heroPhonePreview == nil
            && !isBlackoutHolding
            && !isLiveFromOtherShow
            && !isLiveOutputLocked
            && !ShowLiveSession.shared.isRemoteOperator
            && LiveOverlayController.shared.hasLiveOverlays
    }

    /// Re-reads `allowsHeroOverlayAdjust` onto the hero.
    func syncHeroOverlayAdjust() {
        liveHeader.allowsOverlayAdjust = allowsHeroOverlayAdjust
    }

    // MARK: - Private

    private func handleHeroOverlayAdjust(_ overlay: RenderedOverlay, isFinal: Bool) {
        let live = LiveOverlayController.shared
        guard isFinal else {
            live.setAdjusting(overlay)
            return
        }
        switch overlay {
        case .card(let card):
            TemplateCardStore.shared.update(id: card.id, config: card.config)
        case .media(let entry):
            MediaOverlayStore.shared.update(entry)
        }
        live.setAdjusting(nil)
    }
}
