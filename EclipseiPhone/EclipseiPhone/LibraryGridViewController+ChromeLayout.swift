//
//  LibraryGridViewController+ChromeLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Tap goes live (red) only with AirPlay, EclipseTV, or Practice Mode.
enum LiveOutputRouting {
    /// Live when a display, EclipseTV, or Practice Mode is available.
    static func canMarkLive(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool
    ) -> Bool {
        airPlayConnected || eclipseTVOnline || practiceMode
    }

    /// Live using the current AirPlay / EclipseTV state.
    @MainActor
    static func canMarkLive(practiceMode: Bool) -> Bool {
        canMarkLive(
            airPlayConnected: ExternalDisplayManager.shared.isConnected,
            eclipseTVOnline: TVLibraryStore.shared.isOnline,
            practiceMode: practiceMode
        )
    }

    /// Web overlays (Live Poll / websites) only reach AirPlay / HDMI or Practice.
    /// Linked EclipseTV stays on the companion library and cannot show a WKWebView.
    static func canPresentWebOverlay(
        airPlayConnected: Bool,
        practiceMode: Bool
    ) -> Bool {
        airPlayConnected || practiceMode
    }

    /// Web overlay using the current AirPlay / Practice state.
    @MainActor
    static func canPresentWebOverlay(practiceMode: Bool) -> Bool {
        canPresentWebOverlay(
            airPlayConnected: ExternalDisplayManager.shared.isConnected,
            practiceMode: practiceMode
        )
    }

    /// Live Poll can use the phone as projector when nothing else is connected.
    /// Linked EclipseTV still cannot render the page, so that path needs AirPlay
    /// / HDMI or Practice Mode.
    static func canHostLivePoll(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool
    ) -> Bool {
        if airPlayConnected || practiceMode { return true }
        return !eclipseTVOnline
    }

    /// Screensaver is the live grid item when a destination is up and nothing else is.
    static func isScreensaverFallbackLive(
        hasOutputDestination: Bool,
        isOverlayLive: Bool,
        isJoinedLive: Bool,
        isBlackSelected: Bool,
        isLogoSelected: Bool,
        hasLibraryLiveItem: Bool,
        hasLiveSlideshow: Bool
    ) -> Bool {
        hasOutputDestination
            && !isOverlayLive
            && !isJoinedLive
            && !isBlackSelected
            && !isLogoSelected
            && !hasLibraryLiveItem
            && !hasLiveSlideshow
    }

    /// Replace/reset updates AirPlay only when that tool is already live.
    static func shouldRefreshLiveAfterReplace(isToolLive: Bool) -> Bool {
        isToolLive
    }

    /// Phone hero plays library video only when it is the output (Practice Mode).
    static func phoneHeroPlaysLibraryVideo(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool
    ) -> Bool {
        practiceMode && !airPlayConnected && !eclipseTVOnline
    }

    /// Grey program monitor when library video is live on AirPlay or EclipseTV.
    static func usesRemoteVideoMonitor(
        isVideo: Bool,
        airPlayConnected: Bool,
        eclipseTVOnline: Bool
    ) -> Bool {
        isVideo && (airPlayConnected || eclipseTVOnline)
    }
}

/// Portrait live preview occludes the grid from the page top through the card.
enum LiveHeroBackdrop {
    /// Shown only for the stacked (portrait) live hero — landscape already
    /// puts the grid in a separate column.
    static func isVisible(showsLiveHero: Bool, isSideBySideChrome: Bool) -> Bool {
        showsLiveHero && !isSideBySideChrome
    }
}

// MARK: - Hero / Grid Chrome (stacked vs side-by-side)

extension LibraryGridViewController {

    /// Open Show asked to show the live preview hero with no AirPlay / HDMI / EclipseTV.
    var prefersDisconnectedLivePreview: Bool {
        isShowMode && (openShow?.previewsWhenDisconnected == true)
    }

    /// Tap marks live (red) when AirPlay, EclipseTV, or Practice Mode is on.
    ///
    /// Otherwise the Show is Preview-only: no live hero, and taps open the
    /// on-device gallery / browser instead of going live.
    var hasLiveOutputDestination: Bool {
        LiveOutputRouting.canMarkLive(practiceMode: prefersDisconnectedLivePreview)
    }

    /// Live hero on an open Show: a real destination, Practice Mode, or a Live
    /// Poll the phone is hosting with no display attached.
    var showsLiveHero: Bool {
        isShowMode && (hasLiveOutputDestination || isLivePollPhoneHeroActive)
    }

    /// Gate, Practice preview, or this Show's active room — show the hero so
    /// the host can run the poll on the phone when AirPlay / HDMI are down.
    var isLivePollPhoneHeroActive: Bool {
        guard isShowMode, let openShowId else { return false }
        if livePollGateMembershipId != nil { return true }
        let store = QuestPollSessionStore.shared
        if let practiceId = store.practiceMembershipId,
           LivePollStore.shared.poll(id: practiceId)?.showId == openShowId {
            return true
        }
        if store.session != nil,
           let membershipId = store.membershipId,
           LivePollStore.shared.poll(id: membershipId)?.showId == openShowId {
            return true
        }
        return false
    }

    /// Phone landscape (`verticalSizeClass == .compact`): live preview left, grid
    /// right. With no hero to pair against, the grid takes the full width instead.
    var prefersSideBySideChrome: Bool {
        showsLiveHero && traitCollection.verticalSizeClass == .compact
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

    /// Installs portrait + landscape constraint sets; activates the stacked layout.
    func installChromeLayout() {
        let safe = view.safeAreaLayoutGuide
        let gutter = Self.sideBySideGutter

        let heroLeading = liveHeader.leadingAnchor.constraint(
            equalTo: view.leadingAnchor, constant: headerInset
        )
        let heroTrailing = liveHeader.trailingAnchor.constraint(
            equalTo: view.trailingAnchor, constant: -headerInset
        )
        let heroCenterX = liveHeader.centerXAnchor.constraint(equalTo: view.centerXAnchor)
        let heroWidth = liveHeader.widthAnchor.constraint(equalToConstant: 160)
        let heroHeight = liveHeader.heightAnchor.constraint(
            equalTo: liveHeader.widthAnchor, multiplier: 9.0 / 16.0
        )
        heroLeading.isActive = false
        heroTrailing.isActive = false
        heroCenterX.isActive = false
        heroWidth.isActive = false
        heroHeight.isActive = false

        heroLeadingConstraint = heroLeading
        heroTrailingConstraint = heroTrailing
        heroCenterXConstraint = heroCenterX
        heroWidthConstraint = heroWidth
        heroHeightConstraint = heroHeight

        let heroTop = liveHeader.topAnchor.constraint(
            equalTo: safe.topAnchor, constant: headerInset
        )
        heroTopConstraint = heroTop
        // Portrait: grid fills the safe area; hero floats above and content scrolls under it.
        //
        // Leading/trailing follow the safe area, not the view. The two are identical in
        // portrait, but this layout also serves landscape Home (no hero), where pinning
        // to the view left the grid a full notch-width wider than its visible area and
        // pushed the last column off screen.
        portraitChromeConstraints = [
            heroTop,
            gridHost.topAnchor.constraint(equalTo: safe.topAnchor),
            gridHost.leadingAnchor.constraint(equalTo: safe.leadingAnchor),
            gridHost.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            gridHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Portrait: opaque plate from the page top through the live card so
            // tiles scrolling under the preview can't show between it and the header.
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            heroSpacer.bottomAnchor.constraint(equalTo: liveHeader.bottomAnchor),
            // Park the landscape ribbon; portrait uses the in-grid section.
            slideshowRibbonView.topAnchor.constraint(equalTo: view.topAnchor),
            slideshowRibbonView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            slideshowRibbonView.widthAnchor.constraint(equalToConstant: 0),
            slideshowRibbonView.heightAnchor.constraint(equalToConstant: 0)
        ]

        let ribbonTop = slideshowRibbonView.topAnchor.constraint(
            equalTo: liveHeader.bottomAnchor
        )
        let ribbonHeight = slideshowRibbonView.heightAnchor.constraint(
            equalToConstant: 0
        )
        dockedRibbonTopConstraint = ribbonTop
        dockedRibbonHeightConstraint = ribbonHeight

        // Landscape: live preview leading (top-aligned), grid in the trailing column.
        // The live slideshow ribbon docks under the preview, matching portrait.
        // The ambient mini player is a compact trailing card on the parent VC.
        landscapeChromeConstraints = [
            gridHost.topAnchor.constraint(equalTo: safe.topAnchor),
            gridHost.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            gridHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            gridHost.leadingAnchor.constraint(
                equalTo: liveHeader.trailingAnchor, constant: gutter
            ),
            liveHeader.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor, constant: headerInset
            ),
            liveHeader.topAnchor.constraint(
                equalTo: safe.topAnchor, constant: headerInset
            ),
            liveHeader.bottomAnchor.constraint(
                lessThanOrEqualTo: safe.bottomAnchor, constant: -8
            ),
            slideshowRibbonView.leadingAnchor.constraint(
                equalTo: liveHeader.leadingAnchor
            ),
            slideshowRibbonView.trailingAnchor.constraint(
                equalTo: liveHeader.trailingAnchor
            ),
            ribbonTop,
            ribbonHeight,
            slideshowRibbonView.bottomAnchor.constraint(
                lessThanOrEqualTo: safe.bottomAnchor, constant: -8
            ),
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.widthAnchor.constraint(equalToConstant: 0),
            heroSpacer.heightAnchor.constraint(equalToConstant: 0)
        ]

        NSLayoutConstraint.activate(portraitChromeConstraints)
        isSideBySideChrome = false
        updateLiveHeroBackdrop()
        view.bringSubviewToFront(liveHeader)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: gridHost.centerXAnchor),
            emptyLabel.leadingAnchor.constraint(
                equalTo: gridHost.leadingAnchor, constant: 40
            ),
            emptyLabel.trailingAnchor.constraint(
                equalTo: gridHost.trailingAnchor, constant: -40
            )
        ])
        let emptyTop = emptyLabel.topAnchor.constraint(
            equalTo: gridHost.topAnchor, constant: 160
        )
        emptyTop.isActive = true
        emptyTopConstraint = emptyTop
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
            // Ribbon moves between the Show grid and the leading preview.
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

    /// Sizes the live hero for the active chrome axis and Display Mode.
    func applyHeroChrome() {
        // Home keeps the marketing carousel only — never size/front the live preview.
        guard showsLiveHero else {
            liveHeader.isHidden = true
            liveHeader.clearWebPreview(parking: true)
            liveHeader.clearScreensaverPreview()
            updateLiveHeroBackdrop()
            syncHeroOverlayInsets(preservingProgress: currentHeroScrollProgress())
            updateHeroCollapse()
            layoutDockedSlideshowRibbon()
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

    /// Expanded hero height + breathing room under it. Derived from geometry rather
    /// than measured bounds so a Display Mode change can't leave a stale inset.
    func expandedHeroOverlayInset() -> CGFloat {
        headerInset + estimatedExpandedHeroHeight() + heroBottomPadding
    }

    /// Estimated 16:9 / 9:16 hero height before the first layout pass.
    func estimatedExpandedHeroHeight() -> CGFloat {
        if ExternalOutputSettings.isVerticalMode {
            return verticalHeroMaxHeight
        }
        let bleedWidth = max(0, view.bounds.width - headerInset * 2)
        let bleedHeight = bleedWidth * 9.0 / 16.0
        return min(bleedHeight, verticalHeroMaxHeight)
    }

    // MARK: - Private

    static let sideBySideGutter: CGFloat = 12
    /// Keeps the grid usable when the 16:9 hero would otherwise dominate.
    private static let sideBySideMinGridWidth: CGFloat = 300
    private static let sideBySideMaxHeroWidthFraction: CGFloat = 0.46

    private func applyChromeAxis(sideBySide: Bool) {
        isSideBySideChrome = sideBySide
        deactivateHeroSizeConstraints()
        if sideBySide {
            updateHeroCollapse()
            NSLayoutConstraint.deactivate(portraitChromeConstraints)
            NSLayoutConstraint.activate(landscapeChromeConstraints)
        } else {
            NSLayoutConstraint.deactivate(landscapeChromeConstraints)
            NSLayoutConstraint.activate(portraitChromeConstraints)
            if showsLiveHero {
                view.bringSubviewToFront(liveHeader)
            }
        }
        updateLiveHeroBackdrop()
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
        if bleedHeight > verticalHeroMaxHeight + 0.5 {
            applyCappedHero(aspectWidthOverHeight: 16.0 / 9.0)
        } else {
            applyFullBleedLandscapeHero()
        }
    }

    /// Landscape phone: aspect-fit hero in the leading column (top-aligned).
    private func applySideBySideHeroChrome() {
        deactivateHeroSizeConstraints()
        heroWidthConstraint?.isActive = true

        let safe = view.safeAreaInsets
        let availableWidth = max(
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

        var hero = sideBySideHeroSize(
            availableWidth: availableWidth,
            availableHeight: availableHeight,
            aspect: aspect
        )
        if docksLiveSlideshowRibbon {
            let thumb = Self.slideshowRibbonThumbSize(
                containerWidth: hero.width,
                sectionInset: 0,
                spacing: interitemSpacing
            )
            availableHeight = max(0, availableHeight - Self.sideBySideGutter - thumb.height)
            hero = sideBySideHeroSize(
                availableWidth: availableWidth,
                availableHeight: availableHeight,
                aspect: aspect
            )
        }

        heroWidthConstraint?.constant = hero.width
        let heightConstraint = liveHeader.heightAnchor.constraint(
            equalToConstant: hero.height
        )
        heightConstraint.isActive = true
        heroHeightConstraint = heightConstraint
    }

    /// Aspect-fit hero that leaves at least `sideBySideMinGridWidth` for the grid.
    private func sideBySideHeroSize(
        availableWidth: CGFloat,
        availableHeight: CGFloat,
        aspect: CGFloat
    ) -> CGSize {
        var heroHeight = availableHeight
        var heroWidth = (heroHeight * aspect).rounded(.down)
        let maxWidth = min(
            availableWidth - Self.sideBySideMinGridWidth,
            (view.bounds.width * Self.sideBySideMaxHeroWidthFraction).rounded(.down)
        )
        if maxWidth > 0, heroWidth > maxWidth {
            heroWidth = maxWidth
            heroHeight = (heroWidth / aspect).rounded(.down)
        }
        return CGSize(width: max(120, heroWidth), height: max(68, heroHeight))
    }

    /// Centers a fixed-height hero (Vertical always; Landscape on wide panes).
    private func applyCappedHero(aspectWidthOverHeight: CGFloat) {
        deactivateHeroSizeConstraints()
        heroCenterXConstraint?.isActive = true
        heroWidthConstraint?.isActive = true
        let height = verticalHeroMaxHeight
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
