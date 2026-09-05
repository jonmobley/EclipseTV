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

    /// Docked ribbon follows live output; skip a full rebuild when nothing moved.
    func syncSlideshowRibbonIfChromeChanged() {
        let chrome = SlideshowRibbonChrome(
            inGrid: showsInGridSlideshowRibbon,
            docked: docksLiveSlideshowRibbon
        )
        if SlideshowRibbonChrome.needsLayoutRebuild(
            from: lastSlideshowRibbonChrome, to: chrome
        ) {
            refreshSlideshowRibbonPresentation()
        } else {
            syncLiveSlideshowRibbonChrome()
        }
    }

    /// Hero ribbon toggle + swipe browse while this Show’s slideshow is live.
    /// Live Poll shows its ribbon on program / Practice / Start gate (no toggle).
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

    /// Strip used beside / under the live preview (axis chosen at layout time).
    func makeDockedSlideshowRibbonView() -> UICollectionView {
        let layout = UICollectionViewFlowLayout()
        layout.scrollDirection = .horizontal
        layout.minimumInteritemSpacing = interitemSpacing
        layout.minimumLineSpacing = interitemSpacing
        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.showsVerticalScrollIndicator = false
        view.alwaysBounceHorizontal = true
        view.alwaysBounceVertical = false
        view.isDirectionalLockEnabled = true
        view.contentInsetAdjustmentBehavior = .never
        view.isHidden = true
        view.dataSource = self
        view.delegate = self
        view.prefetchDataSource = self
        view.isPrefetchingEnabled = true
        view.translatesAutoresizingMaskIntoConstraints = false
        view.register(
            LibraryThumbnailCell.self,
            forCellWithReuseIdentifier: LibraryThumbnailCell.reuseIdentifier
        )
        return view
    }

    /// Sizes and shows the docked ribbon under or beside the live preview.
    func layoutDockedSlideshowRibbon() {
        applyDockedRibbonChromeAxis()
        let docked = docksLiveSlideshowRibbon
        let wasHidden = slideshowRibbonView.isHidden
        let vertical = usesVerticalDockedRibbon
        slideshowRibbonView.isHidden = !docked
        slideshowRibbonView.isUserInteractionEnabled = docked
        guard docked else {
            // Parked strip: zero height only. Do not activate a 0-width pin —
            // the strip still shares the hero's leading/trailing, and that pair
            // would collapse the landscape preview to nothing.
            dockedRibbonTopConstraint?.constant = 0
            dockedRibbonHeightConstraint?.constant = 0
            dockedRibbonHeightConstraint?.isActive = true
            dockedRibbonWidthConstraint?.isActive = false
            return
        }
        let thumb = Self.slideshowRibbonThumbSize(
            containerWidth: ribbonThumbContainerWidth(),
            sectionInset: sectionInset,
            spacing: interitemSpacing
        )
        applyDockedRibbonItemSize(thumb, vertical: vertical)
        if vertical {
            dockedRibbonTopConstraint?.constant = 0
            dockedRibbonHeightConstraint?.constant = 0
            dockedRibbonHeightConstraint?.isActive = false
            dockedRibbonWidthConstraint?.constant = thumb.width
            dockedRibbonWidthConstraint?.isActive = true
        } else {
            dockedRibbonTopConstraint?.constant = Self.sideBySideGutter
            dockedRibbonHeightConstraint?.constant =
                Self.dockedSlideshowRibbonHeight(thumbHeight: thumb.height)
            dockedRibbonHeightConstraint?.isActive = true
            dockedRibbonWidthConstraint?.constant = 0
            dockedRibbonWidthConstraint?.isActive = false
        }
        if showsLiveHero {
            view.bringSubviewToFront(liveHeader)
        }
        view.bringSubviewToFront(slideshowRibbonView)
        if wasHidden {
            slideshowRibbonView.reloadData()
        }
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
        let target = Self.dockedRibbonRevealOffset(
            itemFrame: frame,
            bounds: slideshowRibbonView.bounds,
            contentSize: slideshowRibbonView.contentSize,
            contentOffset: slideshowRibbonView.contentOffset,
            adjustedContentInset: slideshowRibbonView.adjustedContentInset,
            scrollsVertically: usesVerticalDockedRibbon
        )
        guard let target else { return }
        slideshowRibbonView.setContentOffset(target, animated: animated)
    }

    /// Breathing room under docked thumbs so they aren't flush with the chrome.
    static let slideshowRibbonBottomPadding: CGFloat = 8

    /// Docked horizontal ribbon height: thumbs plus bottom padding.
    static func dockedSlideshowRibbonHeight(thumbHeight: CGFloat) -> CGFloat {
        thumbHeight + slideshowRibbonBottomPadding
    }

    /// Minimum content offset that fully reveals `itemFrame`, or `nil` if already visible.
    static func dockedRibbonRevealOffset(
        itemFrame: CGRect,
        bounds: CGRect,
        contentSize: CGSize,
        contentOffset: CGPoint,
        adjustedContentInset: UIEdgeInsets,
        scrollsVertically: Bool
    ) -> CGPoint? {
        let inset = adjustedContentInset
        if scrollsVertically {
            let minVisible = contentOffset.y + inset.top
            let maxVisible = contentOffset.y + bounds.height - inset.bottom
            if itemFrame.minY >= minVisible - 0.5, itemFrame.maxY <= maxVisible + 0.5 {
                return nil
            }
            var offsetY = contentOffset.y
            if itemFrame.minY < minVisible {
                offsetY = itemFrame.minY - inset.top
            } else if itemFrame.maxY > maxVisible {
                offsetY = itemFrame.maxY - bounds.height + inset.bottom
            }
            let minY = -inset.top
            let maxY = max(
                minY,
                contentSize.height - bounds.height + inset.bottom
            )
            let clamped = min(max(offsetY, minY), maxY)
            guard abs(clamped - contentOffset.y) > 0.5 else { return nil }
            return CGPoint(x: contentOffset.x, y: clamped)
        }

        let minVisible = contentOffset.x + inset.left
        let maxVisible = contentOffset.x + bounds.width - inset.right
        if itemFrame.minX >= minVisible - 0.5, itemFrame.maxX <= maxVisible + 0.5 {
            return nil
        }
        var offsetX = contentOffset.x
        if itemFrame.minX < minVisible {
            offsetX = itemFrame.minX - inset.left
        } else if itemFrame.maxX > maxVisible {
            offsetX = itemFrame.maxX - bounds.width + inset.right
        }
        let minX = -inset.left
        let maxX = max(
            minX,
            contentSize.width - bounds.width + inset.right
        )
        let clamped = min(max(offsetX, minX), maxX)
        guard abs(clamped - contentOffset.x) > 0.5 else { return nil }
        return CGPoint(x: clamped, y: contentOffset.y)
    }

    private func applyDockedRibbonItemSize(_ thumb: CGSize, vertical: Bool) {
        guard let layout = slideshowRibbonView.collectionViewLayout
            as? UICollectionViewFlowLayout else { return }
        layout.itemSize = thumb
        layout.minimumLineSpacing = interitemSpacing
        layout.minimumInteritemSpacing = interitemSpacing
        layout.sectionInset = UIEdgeInsets(
            top: 0, left: 0,
            bottom: vertical ? 0 : Self.slideshowRibbonBottomPadding,
            right: 0
        )
        layout.scrollDirection = vertical ? .vertical : .horizontal
        slideshowRibbonView.alwaysBounceHorizontal = !vertical
        slideshowRibbonView.alwaysBounceVertical = vertical
        layout.invalidateLayout()
    }
}
