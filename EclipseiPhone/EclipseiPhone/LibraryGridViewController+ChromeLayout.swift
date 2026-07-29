//
//  LibraryGridViewController+ChromeLayout.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hero / Grid Chrome (stacked vs side-by-side)

extension LibraryGridViewController {

    /// The live preview belongs to an open Show; Home is Recent Shows only.
    var showsLiveHero: Bool { isShowMode }

    /// Phone landscape (`verticalSizeClass == .compact`): live preview left, grid
    /// right. With no hero to pair against, the grid takes the full width instead.
    var prefersSideBySideChrome: Bool {
        showsLiveHero && traitCollection.verticalSizeClass == .compact
    }

    /// Shows or hides the live hero for the current mode and relays out around it.
    ///
    /// Hiding parks any embedded web preview so a hidden view can't hold the warm
    /// session, and drops the collapse transform so re-showing starts expanded.
    func updateHeroVisibility() {
        let shouldHide = !showsLiveHero
        guard liveHeader.isHidden != shouldHide else { return }
        liveHeader.isHidden = shouldHide
        if shouldHide {
            liveHeader.clearWebPreview(parking: true)
            liveHeader.transform = .identity
            liveHeader.applyCollapse(progress: 0, scale: 1)
            heroCollapseProgress = 0
            heroExpandTapRecognizer.isEnabled = false
        }
        // Force the guarded work in `updateChromeLayoutIfNeeded` to run: the axis
        // and the grid's top inset both depend on whether the hero is on screen.
        lastLayoutWidth = 0
        lastLayoutHeight = 0
        updateChromeLayoutIfNeeded()
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
        portraitChromeConstraints = [
            heroTop,
            collectionView.topAnchor.constraint(equalTo: safe.topAnchor),
            collectionView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            // Park the unused spacer so it never shows a black band.
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.widthAnchor.constraint(equalToConstant: 0),
            heroSpacer.heightAnchor.constraint(equalToConstant: 0)
        ]

        // Landscape: live preview leading, grid in the trailing column.
        landscapeChromeConstraints = [
            collectionView.topAnchor.constraint(equalTo: safe.topAnchor),
            collectionView.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            collectionView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            collectionView.leadingAnchor.constraint(
                equalTo: liveHeader.trailingAnchor, constant: gutter
            ),
            liveHeader.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor, constant: headerInset
            ),
            liveHeader.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            liveHeader.topAnchor.constraint(
                greaterThanOrEqualTo: safe.topAnchor, constant: 8
            ),
            liveHeader.bottomAnchor.constraint(
                lessThanOrEqualTo: safe.bottomAnchor, constant: -8
            ),
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.widthAnchor.constraint(equalToConstant: 0),
            heroSpacer.heightAnchor.constraint(equalToConstant: 0)
        ]

        NSLayoutConstraint.activate(portraitChromeConstraints)
        isSideBySideChrome = false
        heroSpacer.isHidden = true
        view.bringSubviewToFront(liveHeader)

        NSLayoutConstraint.activate([
            emptyLabel.centerXAnchor.constraint(equalTo: collectionView.centerXAnchor),
            emptyLabel.leadingAnchor.constraint(
                equalTo: collectionView.leadingAnchor, constant: 40
            ),
            emptyLabel.trailingAnchor.constraint(
                equalTo: collectionView.trailingAnchor, constant: -40
            )
        ])
        let emptyTop = emptyLabel.topAnchor.constraint(
            equalTo: collectionView.topAnchor, constant: 160
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
        }
        applyHeroChrome()
        collectionView.collectionViewLayout.invalidateLayout()
    }

    /// Applies Landscape vs Vertical chrome and reloads the active mode's library.
    func applyLayoutMode() {
        // TVLibraryStore also observes this notification and swaps buckets first.
        store.syncLibraryModeFromSettings()
        applyHeroChrome()
        collectionView.collectionViewLayout.invalidateLayout()
        collectionView.reloadData()
    }

    /// Sizes the live hero for the active chrome axis and Display Mode.
    func applyHeroChrome() {
        // Use the applied axis (`isSideBySideChrome`), not traits alone — traits can
        // flip before bounds/constraints catch up (e.g. cold launch in landscape).
        if isSideBySideChrome {
            applySideBySideHeroChrome()
        } else {
            applyStackedHeroChrome()
        }
        syncHeroOverlayInsets(preservingProgress: currentHeroScrollProgress())
        updateHeroCollapse()
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

    /// Top content inset so the grid starts below the floating hero (0 in landscape).
    ///
    /// The inset does not follow the scroll-linked collapse — it stays at the
    /// expanded footprint so the hero can only be tucked while the grid is scrolled,
    /// and returning to the top always reveals the full hero with nothing behind it.
    /// - Parameter preservingProgress: Content scroll progress to keep stable across inset changes.
    func syncHeroOverlayInsets(preservingProgress: CGFloat) {
        let top = (isSideBySideChrome || !showsLiveHero)
            ? 0
            : expandedHeroOverlayInset()

        var inset = collectionView.contentInset
        let topChanged = abs(inset.top - top) > 0.5
        inset.top = top
        inset.bottom = miniPlayerBottomInset + sectionInset
        collectionView.contentInset = inset
        collectionView.verticalScrollIndicatorInsets.top = top
        collectionView.verticalScrollIndicatorInsets.bottom = miniPlayerBottomInset

        if topChanged {
            // Re-pin the same content under the finger (avoid UIKit inset/offset
            // fights), clamped so a bigger viewport can't strand us past the end.
            let pinned = min(max(0, preservingProgress), maxVerticalScroll())
            collectionView.contentOffset = CGPoint(
                x: collectionView.contentOffset.x,
                y: -collectionView.adjustedContentInset.top + pinned
            )
        }

        // Keep the empty-state hint below the floating hero.
        if !isSideBySideChrome {
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

    private static let sideBySideGutter: CGFloat = 12
    /// Keeps the grid usable when the 16:9 hero would otherwise dominate.
    private static let sideBySideMinGridWidth: CGFloat = 240
    private static let sideBySideMaxHeroWidthFraction: CGFloat = 0.58

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
            view.bringSubviewToFront(liveHeader)
        }
        heroSpacer.isHidden = true
    }

    private func deactivateHeroSizeConstraints() {
        heroLeadingConstraint?.isActive = false
        heroTrailingConstraint?.isActive = false
        heroCenterXConstraint?.isActive = false
        heroWidthConstraint?.isActive = false
        heroHeightConstraint?.isActive = false
    }

    /// Portrait: full-bleed 16:9 or capped centered hero (Vertical / wide panes).
    /// Always the expanded size — the scroll-linked collapse is a transform on top.
    func applyStackedHeroChrome() {
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

    /// Landscape phone: aspect-fit hero in the leading column.
    private func applySideBySideHeroChrome() {
        deactivateHeroSizeConstraints()
        heroWidthConstraint?.isActive = true

        let safe = view.safeAreaInsets
        let availableWidth = max(
            0,
            view.bounds.width - safe.left - safe.right - headerInset
                - Self.sideBySideGutter
        )
        let availableHeight = max(
            0,
            view.bounds.height - safe.top - safe.bottom - 16
        )
        let aspect = ExternalOutputSettings.isVerticalMode
            ? (9.0 / 16.0)
            : (16.0 / 9.0)

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
        heroWidth = max(120, heroWidth)
        heroHeight = max(68, heroHeight)

        heroWidthConstraint?.constant = heroWidth
        let heightConstraint = liveHeader.heightAnchor.constraint(
            equalToConstant: heroHeight
        )
        heightConstraint.isActive = true
        heroHeightConstraint = heightConstraint
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
