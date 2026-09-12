//
//  LibraryGridViewController+MediaFit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Screen Fit (Fit / Fill / Custom)

extension LibraryGridViewController {

    /// Fit / Fill / Custom submenu for how an item is framed on the external display.
    ///
    /// Custom opens the pan/zoom editor; Fit and Fill discard any saved position. Video
    /// gets Fit and Fill only — `AVPlayerLayer` has exactly those two gravities, and an
    /// arbitrary crop would need a render-time composition. For a live still the hero
    /// circle is a shortcut for the same two; video changes framing only from here.
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        MediaFitMenu.make(
            forId: item.id,
            allowsCustom: !item.isVideo,
            onSelectFit: { [weak self] mode in
                self?.applyScreenFit(mode, to: item)
            },
            onCustom: { [weak self] in
                self?.onRequestEdit?(item.id)
            }
        )
    }

    /// Saves Fit / Fill, clears any custom position, tells the Apple TV, and
    /// re-pushes the item when it's live so every screen reframes.
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
        if item.isVideo {
            // Re-present through the video path so the seek position survives, the way
            // the Loop and Mute toggles do.
            refreshLiveVideoPresentationIfNeeded(id: item.id)
        } else {
            refreshLivePresentationIfNeeded(for: item)
        }
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
        // Video has Fit / Fill too, but only from its tile menu, next to Loop and Mute.
        // The hero circle sits bottom-trailing, right where a live video puts its
        // scrubber and duration label.
        guard let id = store.currentId,
              let item = store.items.first(where: { $0.id == id }),
              !item.isVideo else {
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            return
        }
        // Custom framing acts like Fill for the hero shortcut icon.
        let mode: MediaFitMode =
            MediaFramingStore.hasFraming(forId: item.id)
            ? .fill
            : MediaFitSettings.mode(forId: item.id)
        liveHeader.setScreenFitToggleVisible(true, mode: mode)
    }

    /// Flips Fit / Fill for the live item or slideshow (hero shortcut).
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
        let next: MediaFitMode =
            MediaFitSettings.mode(forId: item.id) == .fill ? .fit : .fill
        applyScreenFit(next, to: item)
    }
}
