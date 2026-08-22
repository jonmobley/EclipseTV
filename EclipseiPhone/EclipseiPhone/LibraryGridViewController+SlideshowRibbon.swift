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
            isLive: indexPath.item == SlideshowPlaybackController.shared.currentSlideIndex,
            showsTypeIcon: false
        )
    }

    /// Jumps the live slideshow to the tapped ribbon slide.
    func handleLiveSlideshowRibbonTap(at indexPath: IndexPath) {
        SlideshowPlaybackController.shared.goToSlide(at: indexPath.item)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }

    /// Reapplies layout when the live ribbon appears or disappears.
    func refreshSlideshowRibbonPresentation() {
        let wasDocked = !slideshowRibbonView.isHidden
        applyCollectionLayout()
        if isShowMode {
            showCollectionView.reloadData()
        }
        if docksLiveSlideshowRibbon {
            slideshowRibbonView.reloadData()
        }
        if wasDocked != docksLiveSlideshowRibbon {
            lastLayoutWidth = 0
            lastLayoutHeight = 0
            updateChromeLayoutIfNeeded()
        } else {
            layoutDockedSlideshowRibbon()
        }
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
        guard showsLiveSlideshowRibbon else { return }
        let index = SlideshowPlaybackController.shared.currentSlideIndex
        let count = SlideshowPlaybackController.shared.activeSlideIds.count
        guard count > 0, index >= 0, index < count else { return }
        if docksLiveSlideshowRibbon {
            slideshowRibbonView.scrollToItem(
                at: IndexPath(item: index, section: 0),
                at: .centeredHorizontally,
                animated: true
            )
            return
        }
        guard let section = sectionIndex(for: .slideshowRibbon) else { return }
        collectionView.scrollToItem(
            at: IndexPath(item: index, section: section),
            at: .centeredHorizontally,
            animated: true
        )
    }

    /// Horizontal strip used under the landscape live preview.
    func makeDockedSlideshowRibbonView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = interitemSpacing
        layout.minimumLineSpacing = interitemSpacing
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.isDirectionalLockEnabled = true
        view.contentInsetAdjustmentBehavior = .never
        view.isHidden = true
        view.dataSource = self
        view.delegate = self
        view.translatesAutoresizingMaskIntoConstraints = false
        view.register(
            LibraryThumbnailCell.self,
            forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier
        )
        return view
    }

    /// Sizes and shows the docked ribbon under the landscape preview.
    func layoutDockedSlideshowRibbon() {
        let docked = docksLiveSlideshowRibbon
        let wasHidden = slideshowRibbonView.isHidden
        slideshowRibbonView.isHidden = !docked
        slideshowRibbonView.isUserInteractionEnabled = docked
        guard docked else {
            dockedRibbonTopConstraint?.constant = 0
            dockedRibbonHeightConstraint?.constant = 0
            return
        }
        let width = max(
            liveHeader.bounds.width,
            heroWidthConstraint?.constant ?? 0
        )
        let thumb = Self.slideshowRibbonThumbSize(
            containerWidth: width,
            sectionInset: 0,
            spacing: interitemSpacing
        )
        applyDockedRibbonItemSize(thumb)
        dockedRibbonTopConstraint?.constant = Self.sideBySideGutter
        dockedRibbonHeightConstraint?.constant = thumb.height
        view.bringSubviewToFront(slideshowRibbonView)
        if wasHidden {
            slideshowRibbonView.reloadData()
        }
    }

    /// Reloads a visible docked-ribbon thumb after its library image arrives.
    func reloadDockedRibbonThumbnail(for id: String) {
        guard docksLiveSlideshowRibbon,
              let item = SlideshowPlaybackController.shared.activeSlideIds
                .firstIndex(of: id) else { return }
        let path = IndexPath(item: item, section: 0)
        guard slideshowRibbonView.indexPathsForVisibleItems.contains(path) else {
            return
        }
        slideshowRibbonView.reloadItems(at: [path])
    }

    // MARK: - Private

    private func applyDockedRibbonItemSize(_ thumb: CGSize) {
        guard let layout = slideshowRibbonView.collectionViewLayout
            as? UICollectionViewFlowLayout else { return }
        layout.itemSize = thumb
        layout.minimumLineSpacing = interitemSpacing
        layout.minimumInteritemSpacing = interitemSpacing
        layout.sectionInset = .zero
        layout.invalidateLayout()
    }
}
