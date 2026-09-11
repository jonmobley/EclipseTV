//
//  LibraryGridViewController+ExternalDisplay.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - External Display

extension LibraryGridViewController {
    /// The presentation source for the currently live item.
    ///
    /// Used by `ExternalDisplayManager` when a display connects mid-session.
    /// Falls back to the bundled Screensaver so AirPlay never shows a grey idle.
    /// Connection observers mark that fallback as the live Screensaver tile.
    func currentPresentationSource() -> PresentationSource? {
        switch ExternalDisplayManager.shared.overlaySource {
        case .camera:
            if let parked = ExternalDisplayManager.shared.parkedStillPresentationSource {
                return parked
            }
            return .camera
        case .web(let url):
            return .web(url)
        case .webVideo(let link):
            return .webVideo(link)
        case .pdf(let url):
            return .pdf(url)
        case .countdown:
            return .countdown
        case .none:
            break
        }
        if isBlackSelected {
            return .black
        }
        if isScreensaverSelected {
            return ScreensaverStore.presentationSource
        }
        if isLogoSelected {
            return LogoStore.shared.presentationSource
        }
        if let id = store.currentId,
           let item = store.items.first(where: { $0.id == id }) {
            let startAt: TimeInterval
            if item.isVideo {
                startAt = ExternalDisplayManager.shared
                    .currentVideoPlaybackTime(forItemId: id)
                    ?? VideoResumeStore.shared.position(for: id)
                    ?? 0
            } else {
                startAt = 0
            }
            return .forLibraryItem(
                item, thumbnail: store.thumbnail(for: id), startAt: startAt
            )
        }
        return ScreensaverStore.presentationSource
    }

    /// Pushes the currently live item to the external display (if one is connected).
    /// Does not interrupt an active camera/web overlay or a sticky joined presentation.
    func pushCurrentToExternalDisplay() {
        guard ExternalDisplayManager.shared.isConnected else { return }
        guard !ExternalDisplayManager.shared.isOverlayLive else { return }
        guard !ExternalDisplayManager.shared.isJoinedLive else { return }
        if let source = currentPresentationSource() {
            ExternalDisplayManager.shared.present(source)
        }
    }

    /// Reloads the grid unless an interactive reorder is in flight.
    ///
    /// Background stores (thumbnails, slideshows, albums, PDFs, overlay state) post changes
    /// at any time. A `reloadData()` in the middle of `UICollectionView`'s interactive move
    /// invalidates the drag's index paths, which drops the drag and can throw outright.
    /// The order reconciles from the Apple TV's next manifest once arranging finishes.
    func reloadGridIfSafe() {
        guard !isArranging else { return }
        pruneShowSelection()
        reloadLibraryGrid()
    }

    /// Reloads the collection view while keeping on-screen thumbnail pins warm.
    ///
    /// Prefer this over bare `reloadData()` on go-live / live-chrome paths: video decode
    /// often purges `NSCache`, and an unpinned reload paints blank placeholders.
    func reloadLibraryGrid() {
        refreshVisibleThumbnailPins()
        homeCollectionView.reloadData()
        showCollectionView.reloadData()
        slideshowRibbonView.reloadData()
        collectionView.layoutIfNeeded()
        refreshVisibleThumbnailPins()
    }

    /// Clears home-grid live selection when a joined album item becomes the live output.
    func clearLiveSelectionForJoinedPresent() {
        isBlackSelected = false
        isLogoSelected = false
        isScreensaverSelected = false
        store.updateCurrentId(nil)
        reloadLibraryGrid()
        refreshLiveHeader()
    }
}
