//
//  LibraryGridViewController+StoreDelegate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - TVLibraryStoreDelegate

extension LibraryGridViewController: TVLibraryStoreDelegate {
    func libraryStoreDidUpdateItems(_ store: TVLibraryStore) {
        // While actively dragging, keep the working order; it reconciles on finish.
        guard !isArranging else { return }
        // A fresh manifest from the TV confirms any just-saved arrangement.
        arrangeItems = nil
        reloadLibraryGrid()
        updateEmptyState()
        refreshLiveHeader()
    }

    func libraryStoreDidUpdateCurrent(_ store: TVLibraryStore) {
        if store.currentId != nil {
            isBlackSelected = false
            isLogoSelected = false
            isScreensaverSelected = false
        }
        refreshLiveHeader()
        pushCurrentToExternalDisplay()
        guard !isArranging else { return }
        pruneShowSelection()
        // Prefer visible-only repaint: go-live often coincides with video memory
        // pressure that empties NSCache; a full reloadData blanked the whole Show.
        // Fall back when Display Mode just swapped buckets — visible paths can
        // outlive the new data-source counts and crash the per-item update.
        reconfigureVisibleItemsOrReloadGrid()
    }

    /// Repaints on-screen cells in place, or reloads the grid when any path is
    /// out of bounds.
    ///
    /// This fires from `updateCurrentId`, which go-live paths call *before*
    /// `ExternalDisplayManager.present(_:)` ends the previous overlay. At that
    /// instant a live website / PDF tile still reads as live, so this pass paints
    /// a transitional state that the follow-up `reloadLibraryGrid()` corrects in
    /// the same turn. `reconfigureItems` updates the existing cells with no
    /// animation, so that correction lands. The animated `reloadItems` swap it
    /// replaces was still crossfading old cells in when `reloadData()` ran, and
    /// the stale red stroke on the website tile could outlive the reload.
    ///
    /// Bounds come from the data source (not `collectionView.numberOfSections`) so a
    /// layout that still reflects the previous Home/Show shape cannot green-light a
    /// `reconfigureItems` against a shorter bucket.
    private func reconfigureVisibleItemsOrReloadGrid() {
        refreshVisibleThumbnailPins()
        let visible = collectionView.indexPathsForVisibleItems
        guard !visible.isEmpty else {
            reloadLibraryGrid()
            return
        }
        let sectionCount = numberOfSections(in: collectionView)
        let safe = visible.filter { path in
            guard path.section >= 0, path.section < sectionCount else { return false }
            let count = self.collectionView(
                collectionView, numberOfItemsInSection: path.section
            )
            return path.item >= 0 && path.item < count
        }
        if safe.count != visible.count || safe.isEmpty {
            reloadLibraryGrid()
            return
        }
        collectionView.reconfigureItems(at: safe)
        refreshVisibleThumbnailPins()
    }

    func libraryStore(_ store: TVLibraryStore, didUpdateThumbnailFor id: String) {
        if id == store.currentId {
            refreshLiveHeader()
        }
        // Paint in place — `reloadItems` mid-fling rebuilds cells (and ⋯ menus)
        // and hitches scrolling. `cellForItemAt` picks up the cache for tiles that
        // have not appeared yet.
        paintArrivedThumbnail(id)
    }

    func libraryStoreDidChangeConnection(_ store: TVLibraryStore) {
        updateEmptyState()
        // Eclipse TV link also gates the disconnected live hero.
        updateHeroVisibility()
        applyHeroChrome()
        refreshLiveHeader()
        reloadLibraryGrid()
    }

    func libraryStoreDidUpdatePlayback(_ store: TVLibraryStore) {
        if ExternalDisplayManager.shared.isLibraryVideoLive { return }
        liveHeader.updatePlayback(store.playback)
    }
}
