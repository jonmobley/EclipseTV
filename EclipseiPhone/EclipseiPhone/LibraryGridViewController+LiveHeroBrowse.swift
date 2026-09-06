//
//  LibraryGridViewController+LiveHeroBrowse.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Hero Swipe: Previous / Next Still

extension LibraryGridViewController {

    /// Takes live output to the still `delta` steps away in the open Show.
    ///
    /// The hero shows program output, so this is a live change like tapping the
    /// tile — it routes through `presentMedia` for the send, haptic, and grid
    /// reload, and honours the live lock the same way every other live action
    /// does. The grid then scrolls the new tile into view so the swipe and the
    /// thumbnail list never disagree about what is live.
    func browseLiveHero(delta: Int) {
        guard allowsLiveHeroBrowse else { return }
        if blockLiveChangeIfLocked() { return }
        guard let target = LiveHeroBrowse.target(
            from: store.currentId, in: openShowItems, delta: delta
        ) else {
            // End of the Show — no wrap, so say so instead of doing nothing.
            Haptics.warning()
            return
        }
        presentMedia(target)
        revealShowMember(id: target.id)
    }

    /// Enables the hero swipe only while a still from this Show is live.
    func syncLiveHeroBrowseChrome() {
        liveHeader.allowsLibraryBrowse = allowsLiveHeroBrowse
    }

    /// True when a swipe on the hero should walk this Show's stills.
    ///
    /// Every other owner of the hero is excluded: a Slideshow and a Live Poll
    /// take the gesture for their own navigation, and overlays and the tool
    /// tiles (Camera, Background, Blackout, Screensaver) are not part of the
    /// Show's still order, so there is nothing to step through from them.
    var allowsLiveHeroBrowse: Bool {
        guard showsLiveHero, !isLiveFromOtherShow else { return false }
        guard activeLiveSlideshow() == nil,
              !showsLivePollRibbon,
              !liveHeader.isShowingLivePollGate else { return false }
        let manager = ExternalDisplayManager.shared
        guard !manager.isOverlayLive,
              !manager.isWebVideoLive,
              !manager.isParkedOnQuickChangeStill,
              !isBlackSelected,
              !isLogoSelected,
              !isScreensaverSelected else { return false }
        // Locked keeps the gesture so the swipe can explain why nothing moved.
        // With no destination at all, taps open Preview and the hero is a
        // Preview surface too, so leave stepping to the gallery's own paging.
        guard isLiveOutputLocked || hasLiveOutputDestination else { return false }
        return LiveHeroBrowse.canBrowse(from: store.currentId, in: openShowItems)
    }
}
