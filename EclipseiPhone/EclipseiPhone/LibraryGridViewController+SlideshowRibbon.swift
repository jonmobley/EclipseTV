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

    /// Slide or Live Poll count for the live ribbon section.
    func liveSlideshowRibbonItemCount() -> Int {
        if showsLivePollRibbon {
            return livePollRibbonItemCount()
        }
        guard showsLiveSlideshowRibbon else { return 0 }
        return SlideshowPlaybackController.shared.activeSlideIds.count
    }

    /// Configures a ribbon cell for the live slideshow slide at `indexPath`.
    func configureLiveSlideshowRibbonCell(
        _ cell: LibraryThumbnailCell,
        at indexPath: IndexPath
    ) {
        if showsLivePollRibbon {
            configureLivePollRibbonCell(cell, at: indexPath)
            return
        }
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
        if showsLivePollRibbon {
            handleLivePollRibbonTap(at: indexPath)
            return
        }
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
    /// Live Poll always shows its ribbon (no toggle).
    func syncLiveSlideshowRibbonChrome() {
        if showsLivePollRibbon {
            liveHeader.setSlideshowRibbonToggleVisible(false, isOn: false)
            liveHeader.allowsSlideshowBrowse = false
            return
        }
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

    /// Cue-only Live Poll refresh: update highlights; nudge the strip only if needed.
    func reloadLivePollRibbonThumbsForCueChange() {
        reloadLiveSlideshowRibbonThumbs(rebuiltShowGrid: false)
        scrollLiveSlideshowRibbonToCurrentSlide()
    }

    /// Keeps the current slide / poll cue visible without yanking the whole strip.
    ///
    /// Already-visible cues stay put (highlight only). Off-screen cues scroll just
    /// enough to peek into view — never a forced horizontal center.
    func scrollLiveSlideshowRibbonToCurrentSlide() {
        guard showsLiveSlideshowRibbon else { return }
        let index: Int
        let count: Int
        if showsLivePollRibbon {
            index = livePollRibbonIndex
            count = livePollRibbonItems.count
        } else {
            index = SlideshowPlaybackController.shared.currentSlideIndex
            count = SlideshowPlaybackController.shared.activeSlideIds.count
        }
        guard count > 0, index >= 0, index < count else { return }
        if docksLiveSlideshowRibbon {
            scrollDockedRibbonToRevealItem(at: index, animated: true)
            return
        }
        // Legacy in-grid path (unused while the ribbon always docks).
        scrollInGridRibbonHorizontally(to: index)
    }

    /// Horizontal strip used under the live preview.
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

    /// Sizes and shows the docked ribbon under the live preview (both axes).
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
            heroWidthConstraint?.constant ?? 0,
            max(0, view.bounds.width - headerInset * 2)
        )
        let thumb = Self.slideshowRibbonThumbSize(
            containerWidth: width,
            sectionInset: 0,
            spacing: interitemSpacing
        )
        applyDockedRibbonItemSize(thumb)
        dockedRibbonTopConstraint?.constant = Self.sideBySideGutter
        dockedRibbonHeightConstraint?.constant = thumb.height
        if showsLiveHero {
            view.bringSubviewToFront(liveHeader)
        }
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
            reloadDockedRibbonThumbsInPlace()
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

    /// Reloads visible docked thumbs without resetting the strip's offset.
    private func reloadDockedRibbonThumbsInPlace() {
        let expected = liveSlideshowRibbonItemCount()
        let actual = slideshowRibbonView.numberOfItems(inSection: 0)
        if expected != actual {
            slideshowRibbonView.reloadData()
            return
        }
        // Reconfigure in place — `reloadItems` can reset offset and make the
        // whole strip appear to scroll when the highlight moves.
        for path in slideshowRibbonView.indexPathsForVisibleItems {
            guard let cell = slideshowRibbonView.cellForItem(at: path)
                as? LibraryThumbnailCell else { continue }
            configureLiveSlideshowRibbonCell(cell, at: path)
        }
    }

    /// Scrolls the docked ribbon the minimum amount so `index` is fully visible.
    private func scrollDockedRibbonToRevealItem(at index: Int, animated: Bool) {
        let path = IndexPath(item: index, section: 0)
        slideshowRibbonView.layoutIfNeeded()
        guard let frame = slideshowRibbonView.layoutAttributesForItem(at: path)?.frame
        else { return }
        let inset = slideshowRibbonView.adjustedContentInset
        let minVisibleX = slideshowRibbonView.contentOffset.x + inset.left
        let maxVisibleX = slideshowRibbonView.contentOffset.x
            + slideshowRibbonView.bounds.width - inset.right
        // Fully on-screen already — highlight moved; leave offset alone.
        if frame.minX >= minVisibleX - 0.5, frame.maxX <= maxVisibleX + 0.5 {
            return
        }
        var offsetX = slideshowRibbonView.contentOffset.x
        if frame.minX < minVisibleX {
            offsetX = frame.minX - inset.left
        } else if frame.maxX > maxVisibleX {
            offsetX = frame.maxX - slideshowRibbonView.bounds.width + inset.right
        }
        let minX = -inset.left
        let maxX = max(
            minX,
            slideshowRibbonView.contentSize.width - slideshowRibbonView.bounds.width
                + inset.right
        )
        let clamped = min(max(offsetX, minX), maxX)
        let target = CGPoint(x: clamped, y: slideshowRibbonView.contentOffset.y)
        guard abs(target.x - slideshowRibbonView.contentOffset.x) > 0.5 else { return }
        slideshowRibbonView.setContentOffset(target, animated: animated)
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
