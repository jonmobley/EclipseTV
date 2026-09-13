//
//  LibraryGridViewController+ChromeInstall.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Chrome Installation

extension LibraryGridViewController {

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
        // The note card is the bottom-most piece of live chrome. Parked, it
        // collapses onto the ribbon's bottom edge, so this one pin serves both.
        let backdropBottom = heroSpacer.bottomAnchor.constraint(
            equalTo: liveNoteCard.bottomAnchor,
            constant: liveChromeBottomPadding
        )
        heroBackdropBottomConstraint = backdropBottom
        let ribbonTop = slideshowRibbonView.topAnchor.constraint(
            equalTo: liveHeader.bottomAnchor
        )
        let ribbonHeight = slideshowRibbonView.heightAnchor.constraint(
            equalToConstant: 0
        )
        let ribbonWidth = slideshowRibbonView.widthAnchor.constraint(
            equalToConstant: 0
        )
        dockedRibbonTopConstraint = ribbonTop
        dockedRibbonHeightConstraint = ribbonHeight
        dockedRibbonWidthConstraint = ribbonWidth

        // Note card tracks the preview's width in both axes and hangs off the
        // ribbon, so it lands under the strip whenever one is docked.
        let noteTop = liveNoteCard.topAnchor.constraint(
            equalTo: slideshowRibbonView.bottomAnchor
        )
        let noteHeight = liveNoteCard.heightAnchor.constraint(equalToConstant: 0)
        liveNoteTopConstraint = noteTop
        liveNoteHeightConstraint = noteHeight
        NSLayoutConstraint.activate([
            liveNoteCard.leadingAnchor.constraint(equalTo: liveHeader.leadingAnchor),
            liveNoteCard.trailingAnchor.constraint(equalTo: liveHeader.trailingAnchor),
            noteTop,
            noteHeight
        ])

        let gridLeadingFromHero = gridHost.leadingAnchor.constraint(
            equalTo: liveHeader.trailingAnchor, constant: gutter
        )
        let gridLeadingFromRibbon = gridHost.leadingAnchor.constraint(
            equalTo: slideshowRibbonView.trailingAnchor, constant: gutter
        )
        landscapeGridLeadingFromHeroConstraint = gridLeadingFromHero
        landscapeGridLeadingFromRibbonConstraint = gridLeadingFromRibbon

        // Horizontal strip under the hero (portrait + phone / iPad landscape).
        // Height/width constants are applied in `layoutDockedSlideshowRibbon()`.
        horizontalDockedRibbonConstraints = [
            slideshowRibbonView.leadingAnchor.constraint(
                equalTo: liveHeader.leadingAnchor
            ),
            slideshowRibbonView.trailingAnchor.constraint(
                equalTo: liveHeader.trailingAnchor
            ),
            ribbonTop
        ]

        // Unused beside-preview pins (kept inactive; ribbon always docks under).
        verticalDockedRibbonConstraints = [
            slideshowRibbonView.leadingAnchor.constraint(
                equalTo: liveHeader.trailingAnchor, constant: gutter
            ),
            slideshowRibbonView.topAnchor.constraint(
                equalTo: liveHeader.topAnchor
            ),
            slideshowRibbonView.bottomAnchor.constraint(
                equalTo: liveHeader.bottomAnchor
            )
        ]

        // Portrait: grid fills the safe area; hero floats above and content scrolls
        // under it. The live ribbon docks under the hero so Show thumbs scroll alone.
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
            // Opaque plate from the page top through hero + ribbon, so tiles
            // scrolling under the preview can't show between chrome and content.
            // How far it runs past the bottom edge follows the grid's own resting
            // gap — see `liveChromeBottomPadding`.
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            backdropBottom
        ] + horizontalDockedRibbonConstraints

        // Landscape: live preview leading (top-aligned), grid in the trailing column.
        // Ribbon axis (under vs beside the preview) is swapped in
        // `applyDockedRibbonChromeAxis()`. Mini player stays a trailing parent card.
        // Bottom limits are not required: a required pin plus a parked 0-width
        // ribbon used to shove the preview off the clipping pager.
        let heroBottomLimit = liveHeader.bottomAnchor.constraint(
            lessThanOrEqualTo: safe.bottomAnchor, constant: -8
        )
        heroBottomLimit.priority = .defaultHigh
        let ribbonBottomLimit = slideshowRibbonView.bottomAnchor.constraint(
            lessThanOrEqualTo: safe.bottomAnchor, constant: -8
        )
        ribbonBottomLimit.priority = .defaultHigh
        let noteBottomLimit = liveNoteCard.bottomAnchor.constraint(
            lessThanOrEqualTo: safe.bottomAnchor, constant: -8
        )
        noteBottomLimit.priority = .defaultHigh
        landscapeChromeConstraints = [
            gridHost.topAnchor.constraint(equalTo: safe.topAnchor),
            gridHost.trailingAnchor.constraint(equalTo: safe.trailingAnchor),
            gridHost.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            liveHeader.leadingAnchor.constraint(
                equalTo: safe.leadingAnchor, constant: headerInset
            ),
            liveHeader.topAnchor.constraint(
                equalTo: safe.topAnchor, constant: headerInset
            ),
            heroBottomLimit,
            ribbonBottomLimit,
            noteBottomLimit,
            heroSpacer.topAnchor.constraint(equalTo: view.topAnchor),
            heroSpacer.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            heroSpacer.widthAnchor.constraint(equalToConstant: 0),
            heroSpacer.heightAnchor.constraint(equalToConstant: 0)
        ]

        NSLayoutConstraint.activate(portraitChromeConstraints)
        isSideBySideChrome = false
        landscapeGridLeadingFromHeroConstraint?.isActive = false
        landscapeGridLeadingFromRibbonConstraint?.isActive = false
        // Size constants stay out of the axis groups: a parked 0-width ribbon
        // pinned to the hero would collapse the landscape preview to nothing.
        ribbonHeight.isActive = true
        ribbonWidth.isActive = false
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
}
