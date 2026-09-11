//
//  LibraryGridViewController+ChromeLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hero / Grid Chrome (stacked vs side-by-side)

extension LibraryGridViewController {

    /// Side-by-side chrome: phone landscape (compact height) or a wide pane
    /// (iPad landscape, or a rotation frame whose bounds have already flipped).
    var prefersSideBySideChrome: Bool {
        Self.prefersSideBySideChrome(
            showsLiveHero: showsLiveHero,
            verticalSizeClass: traitCollection.verticalSizeClass,
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            bounds: view.bounds.size
        )
    }

    /// Vertical filmstrip beside the preview. Reserved for future use; iPad and
    /// phone always dock the live ribbon under the main preview.
    var usesVerticalDockedRibbon: Bool {
        Self.usesVerticalDockedRibbon(
            isSideBySide: isSideBySideChrome,
            horizontalSizeClass: traitCollection.horizontalSizeClass
        )
    }

    /// Whether live chrome should run side-by-side for the given traits and pane.
    ///
    /// Compact height is phone landscape. `width > height` covers iPad landscape
    /// and a rotation frame where bounds have flipped but `verticalSizeClass`
    /// is still `.regular` — that lag used to keep the stacked (centered) hero
    /// and hide the left-aligned preview.
    static func prefersSideBySideChrome(
        showsLiveHero: Bool,
        verticalSizeClass: UIUserInterfaceSizeClass,
        horizontalSizeClass: UIUserInterfaceSizeClass,
        bounds: CGSize
    ) -> Bool {
        _ = horizontalSizeClass
        guard showsLiveHero else { return false }
        if verticalSizeClass == .compact { return true }
        return bounds.width > bounds.height
    }

    /// Always false: live ribbon docks under the preview on every device.
    static func usesVerticalDockedRibbon(
        isSideBySide: Bool,
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> Bool {
        _ = isSideBySide
        _ = horizontalSizeClass
        return false
    }

    /// Shows or hides the live hero for the current mode and relays out around it.
    ///
    /// Hiding parks any embedded web preview so a hidden view can't hold the warm
    /// session, and drops the collapse transform so re-showing starts expanded.
    /// Always re-applies the Home vs Show visibility — never leave a live preview
    /// sitting on top of the Home marketing carousel.
    func updateHeroVisibility() {
        let shouldHide = !showsLiveHero
        let visibilityChanged = liveHeader.isHidden != shouldHide
        liveHeader.isHidden = shouldHide
        liveHeader.isUserInteractionEnabled = !shouldHide
        if shouldHide {
            liveHeader.clearWebPreview(parking: true)
            liveHeader.clearScreensaverPreview()
            liveHeader.clearCameraPreview()
            liveHeader.transform = .identity
            liveHeader.applyCollapse(progress: 0, scale: 1)
            heroCollapseProgress = 0
            refreshForeignLivePreview()
        }
        // Always relayout when hiding — a stuck visible hero can already report
        // `isHidden == true` after a partial teardown (See All page-sheet dismiss
        // often skips `viewWillAppear`), and skipping layout leaves it on screen.
        guard visibilityChanged || shouldHide else { return }
        // Force the guarded work in `updateChromeLayoutIfNeeded` to run: the axis
        // and the grid's top inset both depend on whether the hero is on screen.
        lastLayoutWidth = 0
        lastLayoutHeight = 0
        updateChromeLayoutIfNeeded()
    }

    /// Home-only: force the live preview off the marketing carousel.
    ///
    /// Call after leaving a Show, when See All dismisses, and on appear while Home
    /// is showing — page sheets often skip `viewWillAppear` on the presenter.
    func enforceHomeLiveHeroTeardownIfNeeded() {
        guard !isShowMode else { return }
        isLogoSelected = false
        updateHeroVisibility()
        applyHeroChrome()
        refreshLiveHeader()
    }

    /// Switches stacked ↔ side-by-side and resizes the hero when geometry changes.
    func updateChromeLayoutIfNeeded() {
        let width = view.bounds.width
        let height = view.bounds.height
        guard width > 0, height > 0 else { return }

        let sideBySide = prefersSideBySideChrome
        let axisChanged = sideBySide != isSideBySideChrome
        let sizeChanged = abs(width - lastLayoutWidth) > 0.5
            || abs(height - lastLayoutHeight) > 0.5
        guard axisChanged || sizeChanged else { return }

        lastLayoutWidth = width
        lastLayoutHeight = height

        if axisChanged {
            applyChromeAxis(sideBySide: sideBySide)
            // Hero/ribbon width changes with the axis; keep Show layout current.
            applyShowPageLayout()
            if isShowMode {
                showCollectionView.reloadData()
            }
        }
        applyHeroChrome()
        invalidatePageLayouts()
    }

    /// Applies Landscape vs Vertical chrome and reloads the active mode's library.
    func applyLayoutMode() {
        let modeBefore = store.activeLibraryMode
        // End arrange/select first so store delegates are not skipped mid-swap.
        if isArranging {
            cancelArranging()
        }
        if isSelecting {
            cancelSelecting()
        }
        // Sync swaps buckets and reloads via store delegates when the mode changed.
        store.syncLibraryModeFromSettings()
        applyHeroChrome()
        invalidatePageLayouts()
        // Avoid a second reloadData on top of the bucket-swap delegate cascade.
        if store.activeLibraryMode == modeBefore {
            reloadLibraryGrid()
        }
    }

    /// Sizes the live hero for the active chrome axis and Display Mode, instantly.
    ///
    /// Callers should use `applyHeroChrome()`, which animates the pass when the
    /// docked ribbon is appearing or disappearing under an on-screen hero.
    func applyHeroChromeNow() {
        // Home keeps the marketing carousel only — never size/front the live preview.
        guard showsLiveHero else {
            liveHeader.isHidden = true
            liveHeader.clearWebPreview(parking: true)
            liveHeader.clearScreensaverPreview()
            liveHeader.clearCameraPreview()
            updateLiveHeroBackdrop()
            syncHeroOverlayInsets(preservingProgress: currentHeroScrollProgress())
            updateHeroCollapse()
            layoutDockedSlideshowRibbon()
            layoutLiveNoteCard()
            return
        }
        // Use the applied axis (`isSideBySideChrome`), not traits alone — traits can
        // flip before bounds/constraints catch up (e.g. cold launch in landscape).
        if isSideBySideChrome {
            applySideBySideHeroChrome()
        } else {
            applyStackedHeroChrome()
        }
        updateLiveHeroBackdrop()
        syncHeroOverlayInsets(preservingProgress: currentHeroScrollProgress())
        updateHeroCollapse()
        layoutDockedSlideshowRibbon()
        layoutLiveNoteCard()
    }

    /// How far the grid has scrolled into content (0 = top).
    func currentHeroScrollProgress() -> CGFloat {
        collectionView.contentOffset.y + collectionView.adjustedContentInset.top
    }

    /// Largest legal content progress for the current insets and content size.
    func maxVerticalScroll() -> CGFloat {
        let viewport = collectionView.bounds.height
            - collectionView.adjustedContentInset.top
            - collectionView.adjustedContentInset.bottom
        return max(0, collectionView.contentSize.height - viewport)
    }

    /// Top content inset so the grid starts below the pinned hero (0 in landscape).
    ///
    /// The inset stays at the expanded footprint so tiles scroll under the card.
    /// - Parameter preservingProgress: Content scroll progress to keep stable across inset changes.
    func syncHeroOverlayInsets(preservingProgress: CGFloat) {
        let top = (isSideBySideChrome || !showsLiveHero)
            ? 0
            : expandedHeroOverlayInset()
        // Home already pads via section insets + safe area; the extra sectionInset
        // on contentInset.bottom was a ~16pt dead scroll bump. Show mode still
        // wants that breathing room under the last media row.
        let bottom = isShowMode
            ? miniPlayerBottomInset + sectionInset
            : miniPlayerBottomInset

        var inset = collectionView.contentInset
        let topChanged = abs(inset.top - top) > 0.5
        let bottomChanged = abs(inset.bottom - bottom) > 0.5
        inset.top = top
        inset.bottom = bottom
        collectionView.contentInset = inset
        collectionView.verticalScrollIndicatorInsets.top = top
        collectionView.verticalScrollIndicatorInsets.bottom = miniPlayerBottomInset

        if topChanged || bottomChanged {
            // Re-pin the same content under the finger (avoid UIKit inset/offset
            // fights), clamped so a bigger viewport can't strand us past the end.
            let pinned = min(max(0, preservingProgress), maxVerticalScroll())
            collectionView.contentOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: -collectionView.adjustedContentInset.top + pinned
            )
        }

        // Keep the empty-state hint below the floating hero / Recent Shows row.
        if !isShowMode {
            updateEmptyState()
        } else if !isSideBySideChrome {
            emptyTopConstraint?.constant = top + 24
        }
    }

    /// Black band the plate and the grid's resting inset add below the
    /// bottom-most piece of live chrome.
    ///
    /// Under the hero card that is `heroBottomPadding`. A docked ribbon already
    /// carries `slideshowRibbonBottomPadding` inside its own height, so the plate
    /// stops at the strip's edge instead — stacking both left a dead black band
    /// under the thumbs taller than the thumbs' own breathing room.
    var liveChromeBottomPadding: CGFloat {
        Self.liveChromeBottomPadding(
            heroBottomPadding: heroBottomPadding,
            ribbonDocked: docksLiveSlideshowRibbon,
            noteDocked: showsLiveNote
        )
    }

    /// Black band under the hero card, or 0 when a padded ribbon is docked.
    ///
    /// The note card sits below both and carries no padding of its own, so it
    /// restores the band whenever it is showing.
    static func liveChromeBottomPadding(
        heroBottomPadding: CGFloat,
        ribbonDocked: Bool,
        noteDocked: Bool = false
    ) -> CGFloat {
        if noteDocked { return heroBottomPadding }
        return ribbonDocked ? 0 : heroBottomPadding
    }

    /// Expanded hero height + docked ribbon + breathing room under them.
    /// Derived from geometry rather than measured bounds so a Display Mode
    /// change can't leave a stale inset.
    func expandedHeroOverlayInset() -> CGFloat {
        var inset = headerInset + estimatedExpandedHeroHeight()
            + liveChromeBottomPadding
        if docksLiveSlideshowRibbon {
            let thumb = Self.slideshowRibbonThumbSize(
                containerWidth: ribbonThumbContainerWidth(),
                sectionInset: sectionInset,
                spacing: interitemSpacing
            )
            inset += Self.sideBySideGutter
                + Self.dockedSlideshowRibbonHeight(thumbHeight: thumb.height)
        }
        if showsLiveNote {
            inset += Self.liveNoteTopGap(ribbonDocked: docksLiveSlideshowRibbon)
                + measuredLiveNoteHeight()
        }
        return inset
    }

    /// Estimated 16:9 / 9:16 hero height before the first layout pass.
    func estimatedExpandedHeroHeight() -> CGFloat {
        let aspect: CGFloat = ExternalOutputSettings.isVerticalMode
            ? 9.0 / 16.0 : 16.0 / 9.0
        let maxHeight = stackedHeroMaxHeight(aspectWidthOverHeight: aspect)
        if ExternalOutputSettings.isVerticalMode {
            return maxHeight
        }
        let bleedWidth = max(0, view.bounds.width - headerInset * 2)
        let bleedHeight = bleedWidth * 9.0 / 16.0
        return min(bleedHeight, maxHeight)
    }

    /// Stacked live-preview height for this pane and Display Mode aspect.
    private func stackedHeroMaxHeight(aspectWidthOverHeight: CGFloat) -> CGFloat {
        StackedHeroMetrics.maxHeight(
            containerSize: view.bounds.size,
            horizontalSizeClass: traitCollection.horizontalSizeClass,
            headerInset: headerInset,
            safeAreaInsets: view.safeAreaInsets,
            aspectWidthOverHeight: aspectWidthOverHeight
        )
    }

    // MARK: - Private

    static let sideBySideGutter: CGFloat = 12
    /// Keeps the grid usable when the 16:9 hero would otherwise dominate (phone).
    static let sideBySideMinGridWidth: CGFloat = 300
    /// Regular-width panes keep a wider trailing grid so 4-up tiles stay usable.
    static let sideBySideRegularMinGridWidth: CGFloat = 420
    static let sideBySideMaxHeroWidthFraction: CGFloat = 0.46
    /// Soft ceiling on iPad so the leading preview cannot swallow the grid.
    static let sideBySideRegularMaxHeroWidthFraction: CGFloat = 0.58

    /// Minimum trailing-grid width for the current size class.
    static func sideBySideMinGridWidth(
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> CGFloat {
        horizontalSizeClass == .regular
            ? sideBySideRegularMinGridWidth
            : sideBySideMinGridWidth
    }

    private func applyChromeAxis(sideBySide: Bool) {
        isSideBySideChrome = sideBySide
        deactivateHeroSizeConstraints()
        if sideBySide {
            updateHeroCollapse()
            NSLayoutConstraint.deactivate(portraitChromeConstraints)
            NSLayoutConstraint.activate(landscapeChromeConstraints)
            if showsLiveHero {
                view.bringSubviewToFront(liveHeader)
            }
        } else {
            NSLayoutConstraint.deactivate(landscapeChromeConstraints)
            NSLayoutConstraint.deactivate(verticalDockedRibbonConstraints)
            landscapeGridLeadingFromHeroConstraint?.isActive = false
            landscapeGridLeadingFromRibbonConstraint?.isActive = false
            NSLayoutConstraint.activate(portraitChromeConstraints)
            if showsLiveHero {
                view.bringSubviewToFront(liveHeader)
                if docksLiveSlideshowRibbon {
                    view.bringSubviewToFront(slideshowRibbonView)
                }
            }
        }
        applyDockedRibbonChromeAxis()
        updateLiveHeroBackdrop()
    }

    /// Pins the docked ribbon under the hero (portrait + landscape).
    ///
    /// The strip always sits below the preview. Vertical beside-preview pins stay
    /// inactive so a parked zero-height ribbon cannot collapse the hero height.
    func applyDockedRibbonChromeAxis() {
        NSLayoutConstraint.deactivate(verticalDockedRibbonConstraints)
        landscapeGridLeadingFromRibbonConstraint?.isActive = false
        if isSideBySideChrome {
            landscapeGridLeadingFromHeroConstraint?.isActive = true
            NSLayoutConstraint.activate(horizontalDockedRibbonConstraints)
        } else {
            landscapeGridLeadingFromHeroConstraint?.isActive = false
            // Portrait already includes horizontal ribbon pins.
        }
    }

    private func deactivateHeroSizeConstraints() {
        heroLeadingConstraint?.isActive = false
        heroTrailingConstraint?.isActive = false
        heroCenterXConstraint?.isActive = false
        heroWidthConstraint?.isActive = false
        heroHeightConstraint?.isActive = false
    }

    /// Black plate under the portrait live card; hidden on Home and in landscape.
    func updateLiveHeroBackdrop() {
        let show = LiveHeroBackdrop.isVisible(
            showsLiveHero: showsLiveHero,
            isSideBySideChrome: isSideBySideChrome
        )
        heroSpacer.isHidden = !show
        guard show else { return }
        view.insertSubview(heroSpacer, belowSubview: liveHeader)
    }

    /// Portrait: full-bleed 16:9 or capped centered hero (Vertical / wide panes).
    /// Always the expanded size — tiles scroll under this card.
    func applyStackedHeroChrome() {
        // Don't promote a hidden live preview over Home's marketing carousel.
        guard showsLiveHero else { return }
        view.bringSubviewToFront(liveHeader)
        if ExternalOutputSettings.isVerticalMode {
            applyCappedHero(aspectWidthOverHeight: 9.0 / 16.0)
            return
        }
        let bleedWidth = max(0, view.bounds.width - headerInset * 2)
        let bleedHeight = bleedWidth * 9.0 / 16.0
        let maxHeight = stackedHeroMaxHeight(aspectWidthOverHeight: 16.0 / 9.0)
        if bleedHeight > maxHeight + 1 {
            applyCappedHero(aspectWidthOverHeight: 16.0 / 9.0)
        } else {
            applyFullBleedLandscapeHero()
        }
    }

    /// Landscape: aspect-fit hero in the leading column (top-aligned).
    private func applySideBySideHeroChrome() {
        deactivateHeroSizeConstraints()
        heroWidthConstraint?.isActive = true
        view.bringSubviewToFront(liveHeader)

        let safe = view.safeAreaInsets
        var availableWidth = max(
            0,
            view.bounds.width - safe.left - safe.right - headerInset
                - Self.sideBySideGutter
        )
        // Leave room under the preview if a docked mini player reserve is set.
        let miniReserve: CGFloat = sideBySideMiniPlayerHeight > 0
            ? Self.sideBySideGutter + sideBySideMiniPlayerHeight
            : 0
        var availableHeight = max(
            0,
            view.bounds.height - safe.top - safe.bottom
                - headerInset - 8 - miniReserve
        )
        let aspect = ExternalOutputSettings.isVerticalMode
            ? (9.0 / 16.0)
            : (16.0 / 9.0)
        // Plus/Max landscape is `.regular` width — still phone chrome, not iPad.
        let sizeClass = traitCollection.verticalSizeClass == .compact
            ? UIUserInterfaceSizeClass.compact
            : traitCollection.horizontalSizeClass
        let minGrid = Self.sideBySideMinGridWidth(horizontalSizeClass: sizeClass)

        var hero = sideBySideHeroSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            aspect: aspect,
            horizontalSizeClass: sizeClass
        )
        if docksLiveSlideshowRibbon {
            if usesVerticalDockedRibbon {
                // Two-pass: size thumbs from the trailing grid, then reserve width.
                let gridWidth = max(
                    minGrid,
                    availableWidth - hero.width - Self.sideBySideGutter
                )
                let thumb = Self.slideshowRibbonThumbSize(
                    containerWidth: gridWidth,
                    sectionInset: sectionInset,
                    spacing: interitemSpacing
                )
                availableWidth = max(
                    0,
                    availableWidth - Self.sideBySideGutter - thumb.width
                )
                hero = sideBySideHeroSize(
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    aspect: aspect,
                    horizontalSizeClass: sizeClass
                )
            } else {
                let thumb = Self.slideshowRibbonThumbSize(
                    containerWidth: ribbonThumbContainerWidth(
                        sideBySideHeroWidth: hero.width
                    ),
                    sectionInset: sectionInset,
                    spacing: interitemSpacing
                )
                availableHeight = max(
                    0,
                    availableHeight - Self.sideBySideGutter
                        - Self.dockedSlideshowRibbonHeight(thumbHeight: thumb.height)
                )
                hero = sideBySideHeroSize(
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    aspect: aspect,
                    horizontalSizeClass: sizeClass
                )
            }
        }
        if showsLiveNote {
            // Measure against the hero width this pass just settled on; the
            // card spans the preview, so its height follows that column.
            let noteHeight = measuredLiveNoteHeight(width: hero.width)
            if noteHeight > 0 {
                availableHeight = max(
                    0,
                    availableHeight
                        - Self.liveNoteTopGap(ribbonDocked: docksLiveSlideshowRibbon)
                        - noteHeight
                )
                hero = sideBySideHeroSize(
                    availableWidth: availableWidth,
                    availableHeight: availableHeight,
                    aspect: aspect,
                    horizontalSizeClass: sizeClass
                )
            }
        }

        heroWidthConstraint?.constant = hero.width
        let heightConstraint = liveHeader.heightAnchor.constraint(
            equalToConstant: hero.height
        )
        heightConstraint.isActive = true
        heroHeightConstraint = heightConstraint
    }

    /// Aspect-fit hero that leaves a usable trailing grid.
    ///
    /// Phone keeps the 0.46 width fraction. Regular-width (iPad) panes use a
    /// wider min grid and a softer 0.58 ceiling so the preview can grow without
    /// crushing 4-up Show tiles.
    static func sideBySideHeroSize(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        aspect: CGFloat,
        horizontalSizeClass: UIUserInterfaceSizeClass,
        containerWidth: CGFloat,
        minGridWidth: CGFloat? = nil,
        maxHeroWidthFraction: CGFloat? = nil
    ) -> CGSize {
        let minGrid = minGridWidth
            ?? sideBySideMinGridWidth(horizontalSizeClass: horizontalSizeClass)
        let fraction = maxHeroWidthFraction ?? (
            horizontalSizeClass == .regular
                ? sideBySideRegularMaxHeroWidthFraction
                : sideBySideMaxHeroWidthFraction
        )
        var heroHeight = availableHeight
        var heroWidth = (heroHeight * aspect).rounded(.down)
        let maxWidth = min(
            availableWidth - minGrid,
            (containerWidth * fraction).rounded(.down)
        )
        if maxWidth > 0, heroWidth > maxWidth {
            heroWidth = maxWidth
            heroHeight = (heroWidth / aspect).rounded(.down)
        }
        return CGSize(width: max(120, heroWidth), height: max(68, heroHeight))
    }

    private func sideBySideHeroSize(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        aspect: CGFloat,
        horizontalSizeClass: UIUserInterfaceSizeClass
    ) -> CGSize {
        Self.sideBySideHeroSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            aspect: aspect,
            horizontalSizeClass: horizontalSizeClass,
            containerWidth: view.bounds.width
        )
    }

    /// Container width used to size ribbon thumbs relative to the Show grid.
    func ribbonThumbContainerWidth(sideBySideHeroWidth: CGFloat? = nil) -> CGFloat {
        if isSideBySideChrome {
            let safe = view.safeAreaInsets
            let heroWidth = sideBySideHeroWidth
                ?? heroWidthConstraint?.constant
                ?? liveHeader.bounds.width
            let minGrid = Self.sideBySideMinGridWidth(
                horizontalSizeClass: traitCollection.verticalSizeClass == .compact
                    ? .compact
                    : traitCollection.horizontalSizeClass
            )
            var width = view.bounds.width - safe.left - safe.right
                - headerInset - Self.sideBySideGutter - max(0, heroWidth)
            if usesVerticalDockedRibbon, docksLiveSlideshowRibbon {
                // Approximate ribbon width as a scaled grid tile of the remainder.
                let provisional = Self.slideshowRibbonThumbSize(
                    containerWidth: max(minGrid, width),
                    sectionInset: sectionInset,
                    spacing: interitemSpacing
                )
                width -= Self.sideBySideGutter + provisional.width
            }
            return max(0, width)
        }
        return view.bounds.width
    }

    /// Centers a fixed-height hero (Vertical always; Landscape on wide panes).
    private func applyCappedHero(aspectWidthOverHeight: CGFloat) {
        deactivateHeroSizeConstraints()
        heroCenterXConstraint?.isActive = true
        heroWidthConstraint?.isActive = true
        let height = stackedHeroMaxHeight(aspectWidthOverHeight: aspectWidthOverHeight)
        let width = (height * aspectWidthOverHeight).rounded(.down)
        heroWidthConstraint?.constant = width
        let heightConstraint = liveHeader.heightAnchor.constraint(equalToConstant: height)
        heightConstraint.isActive = true
        heroHeightConstraint = heightConstraint
    }

    /// Pins Landscape hero leading/trailing with a 16:9 height.
    private func applyFullBleedLandscapeHero() {
        deactivateHeroSizeConstraints()
        heroLeadingConstraint?.isActive = true
        heroTrailingConstraint?.isActive = true
        let aspect = liveHeader.heightAnchor.constraint(
            equalTo: liveHeader.widthAnchor, multiplier: 9.0 / 16.0
        )
        aspect.isActive = true
        heroHeightConstraint = aspect
    }
}
