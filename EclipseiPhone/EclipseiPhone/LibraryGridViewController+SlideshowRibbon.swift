//
//  LibraryGridViewController+SlideshowRibbon.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Slideshow Ribbon

extension LibraryGridViewController {

    /// In-grid vs docked ribbon placement. Slide index is not part of this.
    struct SlideshowRibbonChrome: Equatable {
        var inGrid: Bool
        var docked: Bool

        /// True when the Show layout must be rebuilt (ribbon appears, hides, or moves).
        static func needsLayoutRebuild(
            from previous: SlideshowRibbonChrome?,
            to next: SlideshowRibbonChrome
        ) -> Bool {
            guard let previous else { return true }
            return previous != next
        }
    }

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

    /// Reapplies layout when the live ribbon appears, hides, or moves.
    ///
    /// Slide advances keep the Show grid's offset; only ribbon thumbs refresh.
    func refreshSlideshowRibbonPresentation() {
        let wasDocked = !slideshowRibbonView.isHidden
        let chrome = SlideshowRibbonChrome(
            inGrid: showsInGridSlideshowRibbon,
            docked: docksLiveSlideshowRibbon
        )
        let rebuildLayout = SlideshowRibbonChrome.needsLayoutRebuild(
            from: lastSlideshowRibbonChrome,
            to: chrome
        )
        lastSlideshowRibbonChrome = chrome
        if rebuildLayout {
            applyCollectionLayout()
            if isShowMode {
                showCollectionView.reloadData()
            }
        }
        reloadLiveSlideshowRibbonThumbs(rebuiltShowGrid: rebuildLayout)
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

    /// Centers the current slide in the ribbon without moving the Show grid.
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
        scrollInGridRibbonHorizontally(to: index)
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

    /// Refreshes ribbon thumbs after a slide change without rebuilding the Show grid.
    private func reloadLiveSlideshowRibbonThumbs(rebuiltShowGrid: Bool) {
        if docksLiveSlideshowRibbon {
            slideshowRibbonView.reloadData()
            return
        }
        guard showsInGridSlideshowRibbon, !rebuiltShowGrid else { return }
        guard let section = sectionIndex(for: .slideshowRibbon) else { return }
        let expected = SlideshowPlaybackController.shared.activeSlideIds.count
        let actual = showCollectionView.numberOfItems(inSection: section)
        if expected != actual {
            showCollectionView.reloadSections(IndexSet(integer: section))
            return
        }
        let paths = showCollectionView.indexPathsForVisibleItems
            .filter { $0.section == section }
        if !paths.isEmpty {
            showCollectionView.reloadItems(at: paths)
        }
    }

    /// Orthogonal ribbon scroller only — never `scrollToItem` on the Show grid.
    private func scrollInGridRibbonHorizontally(to index: Int) {
        guard let section = sectionIndex(for: .slideshowRibbon) else { return }
        let path = IndexPath(item: index, section: section)
        guard let attributes = showCollectionView.layoutAttributesForItem(at: path),
              let nested = inGridRibbonScrollView(section: section) else { return }
        let frame = showCollectionView.convert(attributes.frame, to: nested)
        let x = nested.contentOffset.x + frame.midX - nested.bounds.width / 2
        let maxX = max(0, nested.contentSize.width - nested.bounds.width)
        nested.setContentOffset(
            CGPoint(x: min(max(0, x), maxX), y: nested.contentOffset.y),
            animated: true
        )
    }

    private func inGridRibbonScrollView(section: Int) -> UIScrollView? {
        let visible = showCollectionView.indexPathsForVisibleItems
            .first { $0.section == section }
        guard let path = visible,
              let cell = showCollectionView.cellForItem(at: path) else { return nil }
        var view: UIView? = cell.superview
        while let current = view {
            if let scroll = current as? UIScrollView, scroll !== showCollectionView {
                return scroll
            }
            view = current.superview
        }
        return nil
    }

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
