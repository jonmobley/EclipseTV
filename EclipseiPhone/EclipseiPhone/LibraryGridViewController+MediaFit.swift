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
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        let hasCustom = MediaFramingStore.hasFraming(forId: item.id)
        let current = MediaFitSettings.mode(forId: item.id)
        // Checkmark rides in the trailing image slot rather than `state:` so the
        // selected row keeps the same title inset as the others. See
        // `videoOptionActions` for the UIKit behaviour behind this.
        var actions: [UIMenuElement] = MediaFitMode.allCases.map { mode in
            let isCurrent = !hasCustom && mode == current
            return UIAction(
                title: mode.rawValue,
                image: UIImage(systemName: isCurrent ? "checkmark" : mode.iconName)
            ) { [weak self] _ in
                self?.applyScreenFit(mode, to: item)
            }
        }
        let custom = UIAction(
            title: "Custom",
            image: UIImage(systemName: hasCustom ? "checkmark" : "crop")
        ) { [weak self] _ in
            self?.onRequestEdit?(item.id)
        }
        actions.append(custom)
        return UIMenu(
            title: "Screen Fit",
            image: UIImage(systemName: "aspectratio"),
            children: actions
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
        UISelectionFeedbackGenerator().selectionChanged()
        connectionManager.sendImageFit(id: item.id, isFill: mode == .fill)
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshLivePresentationIfNeeded(for: item)
    }

    /// Saves a custom crop position, tells the Apple TV, and re-pushes when live.
    func applyFraming(_ framing: MediaFraming, to item: LibraryItemDTO) {
        MediaFramingStore.set(framing, forId: item.id)
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

    /// Drops a custom position so Fit / Fill take over again.
    func clearFraming(for item: LibraryItemDTO) {
        guard MediaFramingStore.hasFraming(forId: item.id) else { return }
        MediaFramingStore.clear(forId: item.id)
        UISelectionFeedbackGenerator().selectionChanged()
        let isFill = MediaFitSettings.isFill(forId: item.id)
        connectionManager.sendImageFit(id: item.id, isFill: isFill)
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshLivePresentationIfNeeded(for: item)
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
        let next: MediaFitMode =
            MediaFitSettings.mode(forId: item.id) == .fill ? .fit : .fill
        applyScreenFit(next, to: item)
    }
}
