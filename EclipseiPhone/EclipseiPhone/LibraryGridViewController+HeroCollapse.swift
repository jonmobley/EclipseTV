//
//  LibraryGridViewController+HeroCollapse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Scroll-Linked Floating Live Hero

/// Portrait only: the hero shrinks toward a trailing mini preview as the grid
/// scrolls, tracking the finger 1:1 in both directions.
///
/// Two rules keep this stable. The hero keeps its expanded Auto Layout size and is
/// scaled with a `CGAffineTransform`, so a live `WKWebView` preview never relayouts
/// mid-drag. And the grid's top inset stays at the expanded footprint at all times,
/// so progress is a pure function of `contentOffset` — no inset/offset feedback loop
/// and no rewriting the offset out from under the user.
extension LibraryGridViewController {

    /// Trailing mini-preview width (Landscape / 16:9 content).
    static let compactHeroWidthLandscape: CGFloat = 148
    /// Trailing mini-preview width (Vertical / 9:16 content).
    static let compactHeroWidthVertical: CGFloat = 84
    /// Below this much scrollable content, collapsing would just be bounce.
    static let minHeroCollapseDistance: CGFloat = 88

    /// True once the hero reads as a mini preview (tap target, no transport).
    var isHeroCompact: Bool { heroCollapseProgress > 0.5 }

    /// Recomputes the floating hero from the current scroll offset. Cheap enough
    /// to call from `scrollViewDidScroll` and every layout pass.
    func updateHeroCollapse() {
        guard showsLiveHero, !isSideBySideChrome else {
            applyHeroCollapse(progress: 0)
            return
        }
        guard let distance = heroCollapseDistance() else {
            applyHeroCollapse(progress: 0)
            return
        }
        applyHeroCollapse(progress: currentHeroScrollProgress() / distance)
    }

    /// Restores the full hero when the user taps the mini preview. Driving the
    /// scroll (rather than the hero) keeps the two in sync the whole way up.
    @objc func handleHeroExpandTap() {
        guard isHeroCompact else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        let top = CGPoint(x: collectionView.contentOffset.x,
                          y: -collectionView.adjustedContentInset.top)
        collectionView.setContentOffset(
            top,
            animated: !UIAccessibility.isReduceMotionEnabled
        )
    }

    // MARK: - Private

    /// Scroll distance mapped to a full collapse, or nil when the hero should stay
    /// expanded (landscape hero, unscrollable grid, or no room to shrink into).
    private func heroCollapseDistance() -> CGFloat? {
        guard let target = compactHeroTargetRect() else { return nil }
        let scrollable = maxVerticalScroll()
        guard scrollable >= Self.minHeroCollapseDistance else { return nil }
        // Fully tucked about when the hero's expanded slot has scrolled away, but
        // never demanding more scroll than the content actually has.
        let nominal = expandedHeroOverlayInset()
            - (target.height + headerInset + heroBottomPadding)
        return max(Self.minHeroCollapseDistance, min(nominal, scrollable))
    }

    /// Where the tucked mini preview sits, in the controller view's coordinates.
    /// Uniform scaling means the aspect ratio comes along for free.
    private func compactHeroTargetRect() -> CGRect? {
        let expanded = expandedHeroLayoutFrame()
        guard expanded.width > 1, expanded.height > 1 else { return nil }
        let width = ExternalOutputSettings.isVerticalMode
            ? Self.compactHeroWidthVertical
            : Self.compactHeroWidthLandscape
        guard width < expanded.width else { return nil }
        let height = (expanded.height * (width / expanded.width)).rounded(.down)
        return CGRect(
            x: view.bounds.width - headerInset - width,
            y: view.safeAreaInsets.top + headerInset,
            width: width,
            height: height
        )
    }

    /// Hero frame with any collapse transform ignored — `center` is the layer
    /// position and `bounds` the layout size, neither of which a transform touches.
    private func expandedHeroLayoutFrame() -> CGRect {
        CGRect(
            x: liveHeader.center.x - liveHeader.bounds.width / 2,
            y: liveHeader.center.y - liveHeader.bounds.height / 2,
            width: liveHeader.bounds.width,
            height: liveHeader.bounds.height
        )
    }

    private func applyHeroCollapse(progress: CGFloat) {
        let clamped = min(1, max(0, progress))
        guard let target = compactHeroTargetRect(), clamped > 0 else {
            heroCollapseProgress = 0
            liveHeader.transform = .identity
            liveHeader.applyCollapse(progress: 0, scale: 1)
            heroExpandTapRecognizer.isEnabled = false
            return
        }

        let expanded = expandedHeroLayoutFrame()
        let scale = 1 + (target.width / expanded.width - 1) * clamped
        // Scale about the centre, then translate that centre toward the tucked slot.
        liveHeader.transform = CGAffineTransform(scaleX: scale, y: scale)
            .concatenating(
                CGAffineTransform(
                    translationX: (target.midX - expanded.midX) * clamped,
                    y: (target.midY - expanded.midY) * clamped
                )
            )
        heroCollapseProgress = clamped
        liveHeader.applyCollapse(progress: clamped, scale: scale)
        heroExpandTapRecognizer.isEnabled = isHeroCompact
    }
}
