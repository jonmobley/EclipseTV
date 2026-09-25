//
//  LibraryGridViewController+LiveStroke.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Stroke Reconciliation

extension LibraryGridViewController {

    /// Re-asserts the red live stroke on every visible Show tile from the one
    /// resolved program.
    ///
    /// `reloadData()` is not enough on its own. A single go-live turn also fires
    /// partial, per-cell updates — `reconfigureItems` from `updateCurrentId`, the
    /// Camera tile's own refresh — and those are enqueued while the previous item is
    /// still live, because the stores that own live output are updated one at a time.
    /// A cell whose partial update landed after the reload kept the stroke it was
    /// painted with, which is how a website and the slideshow that replaced it both
    /// ended up red, how a swap between two countdowns left the stroke on the
    /// timer that just stopped, and how leaving Camera for another thumbnail put
    /// the new item on output with no red stroke.
    ///
    /// Every one of those is the grid lying about what is on output, so the stroke
    /// gets a last pass that owns it outright. Visible cells only, and each one is a
    /// single layer write, so this is cheap enough to run on every reload.
    func syncVisibleShowTileLiveStrokes() {
        guard isShowMode, let showsSection = sectionIndex(for: .shows) else { return }
        let items = openShowGridItems
        for path in collectionView.indexPathsForVisibleItems
        where path.section == showsSection {
            guard items.indices.contains(path.item),
                  let cell = collectionView.cellForItem(at: path) as? LibraryThumbnailCell
            else { continue }
            cell.setLive(
                carriesLiveStroke(items[path.item]),
                isLocked: isLiveOutputLocked
            )
        }
    }

    /// Last word after a go-live turn's deferred `reconfigureItems` / Camera-tile
    /// refresh. Those can land after `reloadData()` and paint the previous program.
    func scheduleVisibleShowTileLiveStrokeSync() {
        DispatchQueue.main.async { [weak self] in
            self?.syncVisibleShowTileLiveStrokes()
        }
    }

    /// Whether `item`'s tile should be stroked, matching what configuring it draws.
    ///
    /// A member whose media has not arrived renders as a dimmed placeholder and
    /// refuses the stroke even when it is the resolved program, so reconciliation
    /// has to refuse it too — otherwise this pass would paint a tile red that a
    /// reload immediately paints back.
    private func carriesLiveStroke(_ item: ShowGridItem) -> Bool {
        guard isShowGridItemLive(item) else { return false }
        if case .media(let media) = item, media.isAvailable == false { return false }
        return true
    }
}
