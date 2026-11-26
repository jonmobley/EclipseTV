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
    ///
    /// A still already shaped like the panel drops Fit and Fill, since they are the
    /// same picture there. An unmeasured still keeps them: a row missing because a
    /// thumbnail happened to be purged is worse than a row that does nothing.
    func screenFitMenu(for item: LibraryItemDTO) -> UIMenu {
        MediaFitMenu.make(
            forId: item.id,
            offersFitFill: MediaFitAvailability.offersFitFill(
                forId: item.id,
                isVideo: item.isVideo
            ),
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
        Haptics.selection()
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
        Haptics.selection()
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

    /// Drops a custom position so Fit / Fill take over again.
    func clearFraming(for item: LibraryItemDTO) {
        guard MediaFramingStore.hasFraming(forId: item.id) else { return }
        MediaFramingStore.clear(forId: item.id)
        EclipseSyncController.shared.backend.scheduleMediaPrefsSave(libraryId: item.id)
        Haptics.selection()
        let isFill = MediaFitSettings.isFill(forId: item.id)
        connectionManager.sendImageFit(id: item.id, isFill: isFill)
        reloadLibraryGrid()
        refreshLiveHeader()
        refreshLivePresentationIfNeeded(for: item)
    }

    /// Re-presents the live still when `item` is currently on the external panel.
    ///
    /// A slide of a running slideshow re-presents through the slideshow, so the run
    /// (autoplay, ribbon) carries on with the new framing.
    private func refreshLivePresentationIfNeeded(for item: LibraryItemDTO) {
        let playback = SlideshowPlaybackController.shared
        if let slideshowId = playback.activeSlideshowId,
           playback.currentSlideId == item.id {
            playback.refreshPresentationIfLive(slideshowId: slideshowId)
            return
        }
        let manager = ExternalDisplayManager.shared
        guard store.currentId == item.id,
              !manager.isOverlayLive,
              !manager.isJoinedLive else { return }
        manager.present(
            .forLibraryItem(item, thumbnail: store.thumbnail(for: item.id))
        )
    }

    /// Hero Fit / Fill control while a still or this Show’s slideshow is live.
    ///
    /// The circle appears only when the two framings it switches between are
    /// different pictures, so a still already shaped like the panel doesn't get a
    /// button that changes nothing.
    ///
    /// Once a still or the countdown clock has been pinched or dragged, the circle
    /// turns into a reset arrow (its own icon, so it is never mistaken for Fit /
    /// Fill) that puts it back. That shows even for a panel-shaped still.
    ///
    /// A live slideshow is treated slide by slide: the circle shows the current
    /// slide's own Fit / Fill, and hides on a slide already shaped like the panel.
    ///
    /// Hidden while the still's shape is unknown: the hero has no thumbnail to show
    /// yet either, and `didUpdateThumbnailFor` re-runs this once one lands. A button
    /// that appears late beats one that vanishes under a finger.
    func syncLiveScreenFitChrome() {
        syncHeroOverlayAdjust()
        // A remote phone shows the director's button and sends its tap there;
        // pinch and drag stay with the phone that owns the output.
        if ShowLiveSession.shared.isRemoteOperator {
            liveHeader.directAdjustTarget = nil
            let fit = showsLiveHero ? ShowLiveSession.shared.snapshot?.screenFit : nil
            liveHeader.setScreenFitToggleVisible(
                fit != nil,
                mode: fit?.isFill == true ? .fill : .fit,
                showsReset: fit?.showsReset ?? false
            )
            return
        }
        liveHeader.directAdjustTarget = liveHeroAdjustTarget()
        guard let chrome = liveScreenFitChrome() else {
            liveHeader.setScreenFitToggleVisible(false, mode: .fit)
            return
        }
        liveHeader.setScreenFitToggleVisible(
            true, mode: chrome.mode, showsReset: chrome.showsReset
        )
    }

    /// What the hero's Fit / Fill button shows for the live item, or nil when
    /// there is none to show. One rule for the button on this phone and for
    /// what a remote phone is told, so the two cannot disagree.
    func liveScreenFitChrome() -> (mode: MediaFitMode, showsReset: Bool)? {
        // A phone preview is not program: Fit / Fill here would reframe the TV.
        guard showsLiveHero, !isLiveFromOtherShow, heroPhonePreview == nil else {
            return nil
        }
        if case .countdown(let id) = liveHeroAdjustTarget() {
            let layout = CountdownStore.shared.countdown(id: id)?.layout ?? .default
            return layout != .default ? (.fit, true) : nil
        }
        let mgr = ExternalDisplayManager.shared
        if mgr.isOverlayLive
            || mgr.isParkedOnQuickChangeStill
            || isBlackSelected
            || isLogoSelected
            || isScreensaverSelected {
            return nil
        }
        // Video has Fit / Fill too, but only from its tile menu, next to Loop and Mute.
        // The hero circle sits bottom-trailing, right where a live video puts its
        // scrubber and duration label.
        guard let id = store.currentId,
              let item = store.item(id: id),
              !item.isVideo else {
            return nil
        }
        let isFramed = MediaFramingStore.hasFraming(forId: item.id)
        guard isFramed || MediaFitAvailability.fitDiffersFromFill(forId: item.id) == true else {
            return nil
        }
        return (liveScreenFitMode(forId: item.id), isFramed)
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

    /// Flips Fit / Fill for the live item, or the current slide of a live slideshow
    /// (hero shortcut).
    ///
    /// When the live still or countdown clock has been pinched or dragged, the
    /// circle is a reset instead: the still goes back to its Fit / Fill and the
    /// clock to its default size and place.
    func toggleLiveScreenFit() {
        if sendShowLiveCommandIfOperator(.screenFitToggle) {
            Haptics.selection()
            return
        }
        if case .countdown(let id) = liveHeroAdjustTarget() {
            CountdownStore.shared.setLayout(id: id, layout: .default)
            CountdownClockLayoutPreview.set(nil, for: id)
            Haptics.selection()
            syncLiveScreenFitChrome()
            return
        }
        guard let id = store.currentId,
              let item = store.item(id: id),
              !item.isVideo else { return }
        if MediaFramingStore.hasFraming(forId: item.id) {
            clearFraming(for: item)
            return
        }
        let next: MediaFitMode = liveScreenFitMode(forId: item.id) == .fill ? .fit : .fill
        applyScreenFit(next, to: item)
    }

    // MARK: - Direct Adjust (pinch / drag on the hero)

    /// What a pinch or drag on the hero may change right now, if anything.
    ///
    /// Only the open Show's own live still or countdown, and never while output is
    /// locked, while following a director, or while a slideshow owns the hero (its
    /// swipes step slides, and its framing is per slideshow, not per still).
    /// Also off during Blackout hold: saving a crop re-sends the picture, and the TV
    /// must stay black until Blackout ends.
    func liveHeroAdjustTarget() -> DirectAdjustTarget? {
        guard showsLiveHero,
              heroPhonePreview == nil,
              !isBlackoutHolding,
              !isLiveFromOtherShow,
              !isLiveOutputLocked,
              !ShowLiveSession.shared.isRemoteOperator,
              !showsLivePollPracticeHeader else { return nil }
        let mgr = ExternalDisplayManager.shared
        if mgr.isCountdownLive, let id = CountdownController.shared.liveCountdownId {
            return .countdown(id)
        }
        guard !mgr.isOverlayLive,
              !mgr.isParkedOnQuickChangeStill,
              !mgr.isJoinedLive,
              !isBlackSelected,
              !isLogoSelected,
              !isScreensaverSelected,
              activeLiveSlideshow() == nil,
              let id = store.currentId,
              let item = store.item(id: id),
              !item.isVideo else { return nil }
        return .still(
            id: id,
            mode: MediaFitSettings.mode(forId: id),
            isAdjusted: MediaFramingStore.hasFraming(forId: id)
        )
    }

    /// Countdown clock pinched or dragged on the hero: the output follows while the
    /// fingers move, and the layout is saved when they lift.
    func handleHeroCountdownAdjust(
        id: UUID,
        layout: CountdownClockLayout,
        isFinal: Bool
    ) {
        guard isFinal else {
            CountdownClockLayoutPreview.set(layout, for: id)
            return
        }
        CountdownStore.shared.setLayout(id: id, layout: layout)
        CountdownClockLayoutPreview.set(nil, for: id)
        syncLiveScreenFitChrome()
    }

    /// Still pinched or dragged on the hero: save the position (or go back to plain
    /// Fit / Fill), send it to every screen, and repaint the hero.
    func handleHeroStillAdjust(id: String, outcome: StillFramingGesture.Outcome) {
        guard let item = store.item(id: id) else {
            refreshLiveHeader()
            return
        }
        switch outcome {
        case .custom(let framing):
            applyFraming(framing, to: item)
        case .mode(let mode):
            if MediaFramingStore.hasFraming(forId: id)
                || MediaFitSettings.mode(forId: id) != mode {
                applyScreenFit(mode, to: item)
            } else {
                // Pinched and let go without changing anything: just put the hero
                // back from what is saved.
                refreshLiveHeader()
            }
        }
    }
}
