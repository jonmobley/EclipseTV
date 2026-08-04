//
//  LibraryGridViewController+SlideshowRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Slideshow Ribbon

extension LibraryGridViewController {

    /// Active slideshow when it belongs to the open Show.
    func activeLiveSlideshow() -> Slideshow? {
        guard let id = SlideshowPlaybackController.shared.activeSlideshowId else {
            return nil
        }
        guard let show = SlideshowStore.shared.slideshow(id: id),
              show.showId == openShowId else { return nil }
        return show
    }

    /// Slide count for the live ribbon section.
    func liveSlideshowRibbonItemCount() -> Int {
        guard showsLiveSlideshowRibbon else { return 0 }
        return SlideshowPlaybackController.shared.activeSlideIds.count
    }

    /// Configures a ribbon cell for the live slideshow slide at `indexPath`.
    func configureLiveSlideshowRibbonCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        let playback = SlideshowPlaybackController.shared
        let ids = playback.activeSlideIds
        guard ids.indices.contains(indexPath.item) else { return }
        let id = ids[indexPath.item]
        cell.configure(
            with: LibraryItemDTO(
                id: id,
                name: "Slide \(indexPath.item + 1)",
                isVideo: false,
                duration: 0,
                isAvailable: true
            ),
            thumbnail: store.thumbnail(for: id),
            isLive: false
        )
    }

    /// Jumps the live slideshow to the tapped ribbon slide.
    func handleLiveSlideshowRibbonTap(at indexPath: IndexPath) {
        SlideshowPlaybackController.shared.goToSlide(at: indexPath.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Reapplies layout when the live ribbon appears or disappears.
    func refreshSlideshowRibbonPresentation() {
        applyCollectionLayout()
        syncLiveSlideshowRibbonChrome()
    }

    /// Hero ribbon toggle + swipe browse while this Show’s slideshow is live.
    func syncLiveSlideshowRibbonChrome() {
        guard showsLiveHero, !isLiveFromOtherShow,
              let slideshow = activeLiveSlideshow() else {
            liveHeader.setSlideshowRibbonToggleVisible(false, isOn: false)
            liveHeader.allowsSlideshowBrowse = false
            return
        }
        liveHeader.setSlideshowRibbonToggleVisible(
            true, isOn: slideshow.showRibbonWhenLive
        )
        liveHeader.allowsSlideshowBrowse = showsLiveSlideshowRibbon
    }

    /// Flips `showRibbonWhenLive` for the active slideshow (hero control).
    func toggleLiveSlideshowRibbon() {
        guard let slideshow = activeLiveSlideshow() else { return }
        SlideshowStore.shared.updatePreferences(
            id: slideshow.id,
            showRibbonWhenLive: !slideshow.showRibbonWhenLive
        )
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Keeps the current slide roughly centered in the orthogonal ribbon.
    func scrollLiveSlideshowRibbonToCurrentSlide() {
        guard showsLiveSlideshowRibbon,
              let section = sectionIndex(for: .slideshowRibbon) else { return }
        let index = SlideshowPlaybackController.shared.currentSlideIndex
        let count = SlideshowPlaybackController.shared.activeSlideIds.count
        guard count > 0, index >= 0, index < count else { return }
        let path = IndexPath(item: index, section: section)
        collectionView.scrollToItem(
            at: path,
            at: .centeredHorizontally,
            animated: true
        )
    }
}
