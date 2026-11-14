//
//  LibraryGridViewController+BlackoutHold.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Slideshow that Blackout interrupted, and the slide it was on.
struct BlackoutHeldSlideshow: Equatable {
    let id: UUID
    let index: Int
}

// MARK: - Blackout Hold

/// Blackout holds the audience's screen, not the phone.
///
/// While it is on, the TV stays black and silent and nothing on it changes until
/// Blackout ends. The phone stays fully usable: tile taps open a private Preview
/// (as with Live Lock), the held video can be scrubbed silently in the hero, and
/// ⋯ › Show After Blackout cues what follows. Ending Blackout puts the cue live,
/// or brings back what was live before (a video paused where the operator left it,
/// a slideshow on the slide it was showing).
extension LibraryGridViewController {

    /// Blackout is on for this phone's own output.
    ///
    /// An operator follows the director's program and sends its taps there, so the
    /// hold never turns an operator's tap into a Preview.
    var isBlackoutHolding: Bool {
        isBlackSelected && !ShowLiveSession.shared.isRemoteOperator
    }

    // MARK: Begin / End

    /// Blanks output, remembering what to bring back.
    func beginBlackoutHold() {
        let playback = SlideshowPlaybackController.shared
        blackoutHeldSlideshow = playback.activeSlideshowId.map {
            BlackoutHeldSlideshow(id: $0, index: playback.currentSlideIndex)
        }
        playback.stop()
        // Snapshot before flipping the flag — `currentSourceProvider` prefers black.
        ExternalDisplayManager.shared.beginBlackout()
        isBlackSelected = true
        blackoutCue = nil
        // A phone-played preview (Practice) must not keep playing under Blackout.
        liveHeader.pauseLibraryVideoPreview()
        if store.isOnline {
            AirPlayOverlayPark.parkForBlackout(using: connectionManager)
        } else {
            announceAirPlayOverlayIfLinked()
        }
    }

    /// Ends Blackout: the cue goes live, else what was live before comes back.
    func endBlackoutHold() {
        let mgr = ExternalDisplayManager.shared
        let cue = blackoutCue
        let heldSlideshow = blackoutHeldSlideshow
        let heldItem = blackoutHeldLibraryItem
        let heldVideoAt = heldItem.flatMap { blackoutHeldVideoPosition(for: $0) }

        blackoutCue = nil
        blackoutHeldSlideshow = nil
        isBlackSelected = false
        AirPlayOverlayPark.noteBlackoutEnded()

        if let cue {
            // Straight from black to the cue; restoring first would flash the old
            // picture for a frame.
            mgr.discardBlackoutRestore()
            presentLiveUnattended(cue, videoStartsPaused: true)
            return
        }
        if let heldSlideshow,
           let show = SlideshowStore.shared.slideshow(id: heldSlideshow.id),
           !show.itemIds.isEmpty {
            mgr.discardBlackoutRestore()
            startSlideshow(show, startingAt: heldSlideshow.index)
            return
        }

        mgr.endBlackout(videoStartAt: heldVideoAt)
        if store.isOnline, let heldItem, heldItem.isVideo,
           CaptureStore.shared.record(id: heldItem.id) == nil {
            // A play request also lifts the TV's black cover, and lands it paused
            // on the same frame as AirPlay.
            connectionManager.sendPlayRequest(
                id: heldItem.id,
                startAt: heldVideoAt ?? 0,
                startsPaused: true
            )
        } else if mgr.isOverlayLive {
            announceAirPlayOverlayIfLinked()
        } else {
            _ = AirPlayOverlayPark.clear(using: connectionManager)
        }
    }

    // MARK: What Blackout Holds

    /// The library photo or video Blackout will bring back, if that is what it holds.
    var blackoutHeldLibraryItem: LibraryItemDTO? {
        guard let source = ExternalDisplayManager.shared.blackoutHeldSource else {
            // Apple TV alone: nothing reaches AirPlay, so the TV's current item is it.
            guard store.isOnline, let id = store.currentId else { return nil }
            return store.item(id: id)
        }
        switch source.content {
        case .image, .video, .unavailable:
            guard let id = store.currentId else { return nil }
            return store.item(id: id)
        default:
            return nil
        }
    }

    /// Where the held video comes back: the phone scrub when there was one.
    func blackoutHeldVideoPosition(for item: LibraryItemDTO) -> TimeInterval? {
        guard item.isVideo else { return nil }
        if liveHeader.libraryVideoItemId == item.id {
            return liveHeader.libraryVideoPlaybackState.currentTime
        }
        if let held = ExternalDisplayManager.shared.blackoutHeldSource?.videoStartAt,
           held > 0 {
            return held
        }
        return store.playback.currentTime > 0 ? store.playback.currentTime : nil
    }

    /// Hero while Blackout holds: the held picture, dimmed, with BLACKOUT and Up Next.
    ///
    /// A held video gets a silent phone-only player, paused, so the operator can
    /// line it up. Its transport never reaches the TV while Blackout is on.
    func applyBlackoutHoldHeader() {
        guard let item = blackoutHeldLibraryItem else {
            liveHeader.configureOverlay(
                title: "Blackout",
                systemImage: "moon.fill",
                fillColor: .black
            )
            liveHeader.updatePlayback(PlaybackState())
            return
        }
        if item.isVideo, let url = LocalMediaStore.shared.localURL(forId: item.id) {
            let startAt = blackoutHeldVideoPosition(for: item) ?? 0
            liveHeader.configure(
                with: item,
                thumbnail: nil,
                isOnline: store.isOnline,
                showsLocalTransport: true
            )
            liveHeader.showLibraryVideoPreview(
                url: url,
                itemId: item.id,
                isMuted: true,
                isLooping: item.isLooping ?? false,
                startAt: startAt,
                autoplay: false
            )
            liveHeader.updatePlayback(liveHeader.libraryVideoPlaybackState)
            return
        }
        liveHeader.configure(
            with: item,
            thumbnail: store.thumbnail(for: item.id),
            isOnline: store.isOnline
        )
        liveHeader.clearLibraryVideoPreview()
        liveHeader.updatePlayback(PlaybackState())
    }

    // MARK: Cue

    /// Stable key for comparing a tile with the cue across grid rebuilds.
    static func blackoutCueKey(for item: ShowGridItem) -> String? {
        switch item {
        case .slideshow(let show): return "slideshow:\(show.id.uuidString)"
        default: return item.selectionId
        }
    }

    /// Whether `item` is the tile cued to follow Blackout.
    func isBlackoutCue(_ item: ShowGridItem) -> Bool {
        guard isBlackoutHolding, let cue = blackoutCue,
              let key = Self.blackoutCueKey(for: item) else { return false }
        return Self.blackoutCueKey(for: cue) == key
    }

    /// Spoken / shown name of a cue.
    static func blackoutCueTitle(for item: ShowGridItem) -> String? {
        switch item {
        case .slideshow(let show): return show.name
        case .screensaver: return "Screensaver"
        case .logo: return "Background"
        case .media(let media):
            // File names ("batch_2B7E…") mean nothing to an operator; tiles show
            // no title for untitled media either.
            return MediaTitleStore.title(forId: media.id) ?? (media.isVideo ? "Video" : "Photo")
        case .website(let page): return page.title
        case .pdf(let doc): return doc.title
        default: return nil
        }
    }

    /// Cues `item` (or clears the cue when it is already cued).
    func toggleBlackoutCue(_ item: ShowGridItem) {
        guard isBlackoutHolding, item.canAutoPresentLive else { return }
        if isBlackoutCue(item) {
            blackoutCue = nil
        } else {
            blackoutCue = item
            if let title = Self.blackoutCueTitle(for: item) {
                showPresentationToast("Up next after Blackout: \(title)")
            }
        }
        Haptics.impactLight()
        refreshLiveHeader()
        let visible = collectionView.indexPathsForVisibleItems
        if !visible.isEmpty {
            collectionView.reconfigureItems(at: visible)
        }
    }

    /// ⋯ entry that cues a tile, resolved when the menu opens.
    ///
    /// Menus are built as tiles scroll in, long before Blackout may start, so the
    /// entry decides at open time whether to appear and what to say.
    func blackoutCueMenuElement(for item: ShowGridItem) -> UIMenuElement {
        UIDeferredMenuElement.uncached { [weak self] completion in
            guard let self, self.isBlackoutHolding, item.canAutoPresentLive else {
                completion([])
                return
            }
            let cued = self.isBlackoutCue(item)
            let action = UIAction(
                title: cued ? "Don't Show After Blackout" : "Show After Blackout",
                image: UIImage(systemName: cued ? "forward.end.alt" : "forward.end.fill")
            ) { [weak self] _ in
                self?.toggleBlackoutCue(item)
            }
            completion([action])
        }
    }

    /// Prepends the cue entry to a tile's ⋯ menu.
    func menuWithBlackoutCue(_ menu: UIMenu, for item: ShowGridItem) -> UIMenu {
        guard item.canAutoPresentLive else { return menu }
        return menu.replacingChildren([blackoutCueMenuElement(for: item)] + menu.children)
    }

    // MARK: Taps

    /// Handles a Show tile tap while Blackout holds. True when it was handled.
    ///
    /// Media, websites, PDFs, Background and Screensaver fall through to the
    /// regular Preview branches. Tools with no private Preview explain how to
    /// line them up instead of going live.
    func handleShowTapDuringBlackout(_ item: ShowGridItem) -> Bool {
        guard isBlackoutHolding else { return false }
        switch item {
        case .slideshow:
            explainBlackoutHold(cueable: true)
            return true
        case .website(let page) where page.videoLink != nil:
            explainBlackoutHold(cueable: true)
            return true
        case .camera, .cameraPreset, .livePoll, .countdown, .prompter:
            explainBlackoutHold(cueable: false)
            return true
        case .ptzCamera, .screensaver, .logo, .media, .website, .pdf, .unresolved, .add:
            // PTZ opens its controls without taking program while previewing.
            return false
        }
    }

    /// Toast for a tap Blackout will not put on screen.
    func explainBlackoutHold(cueable: Bool) {
        Haptics.warning()
        showPresentationToast(
            cueable
                ? "Blackout is on. Use ⋯ › Show After Blackout to put this up next."
                : "Blackout is on. Turn it off to go live."
        )
    }
}
