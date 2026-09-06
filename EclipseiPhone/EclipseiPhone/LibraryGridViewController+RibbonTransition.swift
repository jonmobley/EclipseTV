//
//  LibraryGridViewController+RibbonTransition.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Hero + docked-ribbon presentation the last chrome pass applied.
struct LiveChromeState: Equatable {
    var heroVisible: Bool
    var ribbonDocked: Bool

    /// Animate only when the ribbon flips under a hero that stays on screen.
    ///
    /// The hero itself appears and disappears without animation (Show open /
    /// close, display connect), so a ribbon easing in beside an instant hero
    /// would look out of step. The first pass never animates.
    static func animatesRibbonTransition(
        from previous: LiveChromeState?,
        to next: LiveChromeState
    ) -> Bool {
        guard let previous, previous.heroVisible, next.heroVisible else { return false }
        return previous.ribbonDocked != next.ribbonDocked
    }
}

// MARK: - Docked Ribbon Show / Hide Transition

extension LibraryGridViewController {

    static let dockedRibbonTransitionDuration: TimeInterval = 0.32

    /// Sizes the live hero for the active chrome axis and Display Mode.
    ///
    /// When the docked ribbon is appearing or disappearing under a hero that is
    /// already on screen, the hero, ribbon, black plate, and grid inset all ease
    /// to their new frames while the strip cross-fades. Everything else applies
    /// instantly via `applyHeroChromeNow()`.
    func applyHeroChrome() {
        let next = LiveChromeState(
            heroVisible: showsLiveHero,
            ribbonDocked: docksLiveSlideshowRibbon
        )
        let previous = presentedLiveChrome
        presentedLiveChrome = next
        guard LiveChromeState.animatesRibbonTransition(from: previous, to: next),
              view.window != nil,
              !UIAccessibility.isReduceMotionEnabled else {
            applyHeroChromeNow()
            return
        }
        animateDockedRibbonTransition(docked: next.ribbonDocked)
    }

    /// Eases chrome to its new layout while the ribbon fades in or out.
    ///
    /// A hiding strip keeps `isHidden == false` until the animation lands so it
    /// can fade; `layoutDockedSlideshowRibbon()` honours `isFadingOutDockedRibbon`.
    /// A newer transition supersedes the completion of an older one.
    private func animateDockedRibbonTransition(docked: Bool) {
        let ribbon = slideshowRibbonView
        dockedRibbonTransitionToken &+= 1
        let token = dockedRibbonTransitionToken
        isFadingOutDockedRibbon = !docked
        if docked, ribbon.isHidden {
            // Start transparent; a strip caught mid-fade keeps its current alpha.
            ribbon.alpha = 0
        }
        // Settle unrelated pending layout so only this change animates.
        view.layoutIfNeeded()
        UIView.animate(
            withDuration: Self.dockedRibbonTransitionDuration,
            delay: 0,
            options: [.beginFromCurrentState, .allowUserInteraction, .curveEaseInOut],
            animations: { [self] in
                applyHeroChromeNow()
                view.layoutIfNeeded()
                ribbon.alpha = docked ? 1 : 0
            },
            completion: { [weak self] _ in
                guard let self, self.dockedRibbonTransitionToken == token else { return }
                self.isFadingOutDockedRibbon = false
                if !docked {
                    ribbon.isHidden = true
                    ribbon.alpha = 1
                }
            }
        )
    }
}
