//
//  LibraryGridViewController+MediaFit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Screen Fit (Fit / Fill / Custom)

extension LibraryGridViewController {

    /// Fit / Fill / Custom submenu for how a still is framed on the external display.
    ///
    /// Offered on the tile ⋯ menu for stills only — video framing is fixed to
    /// aspect fit. Custom opens the pan/zoom editor; Fit and Fill discard any
    /// saved position. The hero circle is a Fit / Fill shortcut.
    ///
    /// An unmeasured still keeps Fit and Fill: a row missing because a thumbnail
    /// happened to be purged is worse than a row that does nothing.
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        MediaFitMenu.make(
            forId: item.id,
            offersFitFill: MediaFitAvailability.fitDiffersFromFill(forId: item.id) ?? true,
            onSelectFit: { [weak self] mode in
                self?.applyScreenFit(mode, to: item)
            },
            onCustom: { [weak self] in
                self?.onRequestEdit?(item.id)
            }
        )
    }

    /// Saves Fit / Fill, clears any custom position, tells the Apple TV, and
    /// re-pushes the still when it's live so every screen reframes.
    func applyScreenFit(_ mode: MediaFitMode, to item: LibraryItemDTO) {
        let hadFraming = MediaFramingStore.hasFraming(forId: item.id)
        let modeChanged = MediaFitSettings.mode(forId: item.id) != mode
        guard modeChanged || hadFraming else { return }
        MediaFramingStore.clear(forId: item.id)
        MediaFitSettings.setMode(mode, forId: item.id)
        EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: item.id)
        UISelectionFeedbackGenerator().selectionChanged()
        connectionManager.sendImageFit(id: item.id, isFill: mode == .fill)
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshLivePresentationIfNeeded(for: item)
    }

    /// Saves a custom crop position, tells the Apple TV, and re-pushes when live.
    func applyFraming(_ framing: MediaFraming, to item: LibraryItemDTO) {
        MediaFramingStore.set(framing, forId: item.id)
        logAppliedFraming(framing, to: item)
        ReframeLog.watchedId = item.id
        EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: item.id)
        UISelectionFeedbackGenerator().selectionChanged()
        connectionManager.sendImageFit(
            id: item.id,
            isFill: true,
            framing: framing
        )
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshLivePresentationIfNeeded(for: item)
    }

    /// Traces what the grid will derive from the framing just written, so the console
    /// shows the stored unit rect, what came back from the store, and the tile crop.
    private func logAppliedFraming(_ framing: MediaFraming, to item: LibraryItemDTO) {
        let thumb = store.thumbnail(for: item.id)
        let readBack = MediaFramingStore.framing(forId: item.id)
        let resolved = thumb.flatMap { framing.resolvedRect(in: $0.size) }
        let framed = MediaFramingStore.framedStill(
            thumb, forId: item.id, fallback: .scaleAspectFill
        )
        ReframeLog.emit("""
        [Reframe] APPLY id=\(item.id) target=\(ReframeLog.fmt(MediaAspect.activeTarget))
          written \(ReframeLog.framing(framing)) readBack \(ReframeLog.framing(readBack))
          thumb \(ReframeLog.image(thumb))
          crop \(resolved.map(ReframeLog.rect) ?? "nil")
          tile \(ReframeLog.image(framed.image)) mode \(framed.contentMode.rawValue)
        """)
    }

    /// Re-presents the live still when `item` is currently on the external panel.
    private func refreshLivePresentationIfNeeded(for item: LibraryItemDTO) {
        let manager = ExternalDisplayManager.shared
        guard store.currentId == item.id,
              !manager.isOverlayLive,
              !manager.isJoinedLive else { return }
        manager.present(
            .forLibraryItem(item, thumbnail: store.thumbnail(for: item.id))
        )
    }

    /// Fit / Fill submenu for a slideshow's live framing.
    func screenFitMenu(for slideshow: Slideshow) -> UIMenu {
        let current: MediaFitMode = slideshow.isFill ? .fill : .fit
        let actions = MediaFitMode.allCases.map { mode in
            let isCurrent = mode == current
            return UIAction(
                title: mode.rawValue,
                image: UIImage(systemName: isCurrent ? "checkmark" : mode.iconName)
            ) { [weak self] _ in
                self?.applyScreenFit(mode, to: slideshow)
            }
        }
        return UIMenu(
            title: "Screen Fit",
            image: UIImage(systemName: "aspectratio"),
            children: actions
        )
    }

    /// Saves slideshow Fit / Fill and re-pushes the current slide when that show is live.
    func applyScreenFit(_ mode: MediaFitMode, to slideshow: Slideshow) {
        let isFill = mode == .fill
        guard slideshow.isFill != isFill else { return }
        SlideshowStore.shared.updatePreferences(id: slideshow.id, isFill: isFill)
        UISelectionFeedbackGenerator().selectionChanged()
        SlideshowPlaybackController.shared.refreshPresentationIfLive(
            slideshowId: slideshow.id
        )
        reloadLibraryGrid()
        refreshLiveHeader()
    }

    /// Hero Fit / Fill control while a still or this Show’s slideshow is live.
    ///
    /// The circle appears only when the two framings it switches between are
    /// different pictures, so a still already shaped like the panel doesn't get a
    /// button that changes nothing. That includes a still the user has positioned by
    /// hand: the circle means Fit ↔ Fill, and pressing it into service as "undo my
    /// crop" would be a second verb wearing the same icon. Resetting a matching
    /// still's position lives in the ⋯ Screen Fit menu instead.
    ///
    /// A slideshow keeps the circle whatever its slides look like — the aspect
    /// changes from slide to slide, so the choice still means something.
    ///
    /// Hidden while the still's shape is unknown: the hero has no thumbnail to show
    /// yet either, and `didUpdateThumbnailFor` re-runs this once one lands. A button
    /// that appears late beats one that vanishes under a finger.
    func syncLiveScreenFitChrome() {
        guard showsLiveHero, !isLiveFromOtherShow else {
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            return
        }
        let mgr = ExternalDisplayManager.shared
        if mgr.isOverlayLive
            || mgr.isParkedOnQuickChangeStill
            || isBlackSelected
            || isLogoSelected
            || isScreensaverSelected {
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            return
        }
        if let slideshow = activeLiveSlideshow() {
            liveHeader.setScreenFitToggleVisible(
                true,
                mode: slideshow.isFill ? .fill : .fit
            )
            return
        }
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }),
              !item.isVideo,
              MediaFitAvailability.fitDiffersFromFill(forId: item.id) == true else {
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            return
        }
        liveHeader.setScreenFitToggleVisible(true, mode: liveScreenFitMode(forId: item.id))
    }

    /// Framing the hero circle advertises for `id`: a custom position reads as Fill,
    /// since like Fill it can crop.
    ///
    /// Shared with the tap handler so the icon and what the tap does can't drift —
    /// reading the stored Fit / Fill here and the raw `MediaFitSettings` value there
    /// is what let a framed still show the Fill icon and then apply Fill, silently
    /// dropping the user's position while the icon sat still.
    func liveScreenFitMode(forId id: String) -> MediaFitMode {
        MediaFramingStore.hasFraming(forId: id) ? .fill : MediaFitSettings.mode(forId: id)
    }

    /// Flips Fit / Fill for the live still or slideshow (hero shortcut).
    ///
    /// Also clears any custom position so the toggle always lands on Fit or Fill.
    func toggleLiveScreenFit() {
        if let slideshow = activeLiveSlideshow() {
            applyScreenFit(slideshow.isFill ? .fit : .fill, to: slideshow)
            return
        }
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }),
              !item.isVideo else { return }
        let next: MediaFitMode = liveScreenFitMode(forId: item.id) == .fill ? .fit : .fill
        applyScreenFit(next, to: item)
    }
}
