//
//  LibraryGridViewController+ScrollAnchor.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Grid Scroll Anchor

/// A grid scroll position as a share of its scrollable range, so the same place
/// can be found again after that range reflows.
///
/// An absolute offset stops meaning anything once the tiles reflow: a portrait
/// grid resting on its last row is a landscape grid scrolled past its end, and
/// UIKit clamps that to wherever the shorter content stops. When the phone turns
/// back the offset stays clamped, and the grid comes up rows short of where the
/// user left it. The share survives the reflow — 1 is still the bottom.
struct GridScrollAnchor: Equatable {

    /// 0 at the top of the scrollable range, 1 at its bottom.
    let fraction: CGFloat

    /// Progress past either end counts as that end, so a grid captured
    /// mid-bounce comes back flush to its last row rather than short of it.
    init(progress: CGFloat, maxProgress: CGFloat) {
        guard maxProgress > 0 else {
            fraction = 0
            return
        }
        fraction = min(1, max(0, progress / maxProgress))
    }

    /// Scroll progress at the same share of a range of `maxProgress`.
    func progress(forMaxProgress maxProgress: CGFloat) -> CGFloat {
        guard maxProgress > 0 else { return 0 }
        return fraction * maxProgress
    }
}

// MARK: - Keeping the Grid's Place Across a Reflow

extension LibraryGridViewController {

    /// Below this much scrollable range the grid is treated as fitting on screen:
    /// it is pinned to the top and holds no position worth restoring.
    static let negligibleVerticalScroll: CGFloat = 8

    /// Remembers where the visible page is scrolled before its geometry changes.
    ///
    /// Called from `viewWillTransition` (the phone turns while the grid is up)
    /// and `viewWillDisappear` (a fullscreen screen — website, camera — covers
    /// it and may turn the phone while the grid is detached from the window, so
    /// the grid only meets the new size when it comes back). A page that fits
    /// on screen has no position to offer, so an anchor already waiting for it
    /// is left alone: it is still the last place the user actually chose.
    func captureGridScrollAnchor() {
        let page = collectionView
        let maxProgress = maxVerticalScroll()
        guard maxProgress > Self.negligibleVerticalScroll else {
            if pendingGridScrollAnchor?.page !== page {
                pendingGridScrollAnchor = nil
            }
            return
        }
        let anchor = GridScrollAnchor(
            progress: currentHeroScrollProgress(),
            maxProgress: maxProgress
        )
        pendingGridScrollAnchor = (page: page, anchor: anchor)
    }

    /// Re-applies the pending anchor once the grid has laid out at a new size.
    ///
    /// Runs at the end of `viewDidLayoutSubviews`, after the chrome and the
    /// fit-on-screen pin have had their say, so this is the last word on the
    /// offset. A page that still fits on screen keeps the anchor waiting: the
    /// range that can honour it may only come back with the next turn.
    func restoreGridScrollAnchorIfNeeded() {
        // `gridHost` is a direct subview, so its frame is final here even when
        // the pages inside it have not laid out yet.
        let size = gridHost.bounds.size
        let sizeChanged = size != lastGridLayoutSize
        lastGridLayoutSize = size
        guard sizeChanged, size.width > 0, size.height > 0,
              let pending = pendingGridScrollAnchor,
              pending.page === collectionView else { return }
        let page = pending.page
        guard !page.isDragging, !page.isDecelerating else { return }
        // Content size is only current once the page has laid out at this size.
        page.layoutIfNeeded()
        let maxProgress = maxVerticalScroll()
        guard maxProgress > Self.negligibleVerticalScroll else { return }
        pendingGridScrollAnchor = nil
        page.contentOffset = CGPoint(
            x: page.contentOffset.x,
            y: -page.adjustedContentInset.top
                + pending.anchor.progress(forMaxProgress: maxProgress)
        )
    }

    /// Drops the pending anchor; call when the page's content changes wholesale.
    func discardGridScrollAnchor() {
        pendingGridScrollAnchor = nil
    }

    /// A drag on a page with room to scroll is the user picking a new place, so
    /// whatever was waiting to be restored is stale. A bounce on a page that
    /// fits on screen is not a choice and leaves the anchor waiting.
    func scrollViewWillBeginDragging(_ scrollView: UIScrollView) {
        guard scrollView === collectionView,
              maxVerticalScroll() > Self.negligibleVerticalScroll else { return }
        discardGridScrollAnchor()
    }
}
