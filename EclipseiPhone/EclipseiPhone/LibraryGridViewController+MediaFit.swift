//
//  LibraryGridViewController+MediaFit.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Screen Fit (Fit / Fill)

extension LibraryGridViewController {

    /// Fit / Fill submenu controlling how a still is framed on the external display.
    ///
    /// Offered on the tile ⋯ menu for stills only — video framing is fixed to
    /// aspect fit. The hero circle is a shortcut for the same setting.
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        let current = MediaFitSettings.mode(forId: item.id)
        // Checkmark rides in the trailing image slot rather than `state:` so the
        // selected row keeps the same title inset as the others. See
        // `videoOptionActions` for the UIKit behaviour behind this.
        let actions = MediaFitMode.allCases.map { mode in
            let isCurrent = mode == current
            return UIAction(
                title: mode.rawValue,
                image: UIImage(systemName: isCurrent ? "checkmark" : mode.iconName)
            ) { [weak self] _ in
                self?.applyScreenFit(mode, to: item)
            }
        }
        return UIMenu(
            title: "Screen Fit",
            image: UIImage(systemName: "aspectratio"),
            children: actions
        )
    }

    /// Saves the choice, tells the Apple TV, and re-pushes the still when it's the live
    /// item so every screen reframes without waiting for the next selection.
    func applyScreenFit(_ mode: MediaFitMode, to item: LibraryItemDTO) {
        guard MediaFitSettings.mode(forId: item.id) != mode else { return }
        MediaFitSettings.setMode(mode, forId: item.id)
        UISelectionFeedbackGenerator().selectionChanged()
        connectionManager.sendImageFit(id: item.id, isFill: mode == .fill)
        reloadLibraryGrid()
        refreshLiveHeader()

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
        liveHeader.setScreenFitToggleVisible(
            true,
            mode: MediaFitSettings.mode(forId: item.id)
        )
    }

    /// Flips Fit / Fill for the live still or slideshow (hero shortcut).
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
