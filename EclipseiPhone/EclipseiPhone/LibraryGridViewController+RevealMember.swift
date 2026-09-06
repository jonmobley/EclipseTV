//
//  LibraryGridViewController+RevealMember.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

extension LibraryGridViewController {

    /// Snaps the Show grid to a just-added member so the new thumbnail is on screen.
    func revealAddedShowMember(id: String) {
        revealAddedShowMember(id: id, retry: true)
    }

    /// Snaps to whatever the latest album-store change appended to the open Show.
    ///
    /// Runs on every `LocalAlbumStore.didChangeNotification`, so every add path
    /// (Photos, library picker, PDF, countdown, copy between Shows, …) reveals its
    /// tile without each caller having to remember to. Remote sync applies are
    /// skipped so another device's edits never yank the grid mid-scroll.
    func revealShowMembersAddedSinceLastChange() {
        guard let showId = openShowId else {
            revealedShowSurface = nil
            return
        }
        let current = openShowSurfaceIds
        defer { revealedShowSurface = (showId, Set(current)) }
        guard let previous = revealedShowSurface,
              previous.showId == showId,
              !EclipseSyncController.shared.isApplyingRemote else { return }
        guard let newest = current.last(where: { !previous.ids.contains($0) }) else { return }
        revealAddedShowMember(id: newest)
    }

    /// Records the open Show's surface as already on screen (call when a Show opens).
    func markShowSurfaceRevealed() {
        guard let showId = openShowId else {
            revealedShowSurface = nil
            return
        }
        revealedShowSurface = (showId, Set(openShowSurfaceIds))
    }

    private func revealAddedShowMember(id: String, retry: Bool) {
        reloadGridIfSafe()
        collectionView.layoutIfNeeded()
        guard isShowMode, let section = sectionIndex(for: .shows) else { return }
        if let item = Self.indexOfShowMember(id, in: openShowGridItems) {
            // Jump, don't glide: the new tile must already be in view when the
            // picker dismisses, however long the Show has grown.
            collectionView.scrollToItem(
                at: IndexPath(item: item, section: section),
                at: .centeredVertically,
                animated: false
            )
            return
        }
        guard retry else { return }
        DispatchQueue.main.async { [weak self] in
            self?.revealAddedShowMember(id: id, retry: false)
        }
    }

    /// Brings an existing Show member back into view (Preview close, hero swipe).
    ///
    /// Leaves the grid alone when the tile is already fully on screen. Otherwise it
    /// jumps (no glide) so the tile is in place before the modal finishes dismissing;
    /// the user swiped through the gallery, so the grid should not still be parked
    /// where they left it.
    func revealShowMember(id: String) {
        guard isShowMode, let section = sectionIndex(for: .shows),
              let item = Self.indexOfShowMember(id, in: openShowGridItems) else { return }
        collectionView.revealItemIfNeeded(at: IndexPath(item: item, section: section))
    }

    /// Index of a Show-grid member id (media / website / PDF / slideshow / countdown)
    /// or tool token (Screensaver / Background / Camera).
    static func indexOfShowMember(_ id: String, in items: [ShowGridItem]) -> Int? {
        items.firstIndex { item in
            switch item {
            case .screensaver:
                return id == ShowToolToken.screensaver
            case .logo:
                return id == ShowToolToken.logo
            case .camera:
                return id == ShowToolToken.camera
            case .media(let media):
                return media.id == id
            case .website(let page):
                return page.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
            case .pdf(let doc):
                return doc.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
            case .livePoll(let item):
                return ShowLivePollToken.token(for: item.id)
                    .caseInsensitiveCompare(id) == .orderedSame
            case .slideshow(let show):
                return ShowSlideshowToken.token(for: show.id) == id
                    || show.id.uuidString.caseInsensitiveCompare(id) == .orderedSame
            case .countdown(let item):
                return ShowCountdownToken.token(for: item.id)
                    .caseInsensitiveCompare(id) == .orderedSame
            default:
                return false
            }
        }
    }
}
