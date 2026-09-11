//
//  LibraryGridViewController+LivePollGate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Whether the phone hero may show Live Poll Practice / Start chrome.
///
/// With a projector attached that chrome is phone-only: a live website,
/// countdown, camera, or PDF keeps its own screen until the host taps Start, so
/// it does not block the gate. Anything the phone hero itself is showing —
/// a photo, a Show tool, a running slideshow, or an overlay in Practice Mode —
/// does take the hero back.
enum LivePollIdleChrome {

    /// - Parameters:
    ///   - photoLive: A library still or video is the live item.
    ///   - toolSelected: Blackout, Logo, or Screensaver is selected.
    ///   - slideshowActive: A slideshow is playing.
    ///   - overlayOwnsPhoneHero: A live overlay (countdown, website, camera, PDF)
    ///     has no display to sit on, so the phone hero is the only place it
    ///     exists. Painting the gate over it retired the overlay from the sole
    ///     output while its tile still read live; a card tap ends the overlay
    ///     first (`overlayOwnsPhoneHero(...)`) so this only guards repaints.
    static func isAvailable(
        photoLive: Bool,
        toolSelected: Bool,
        slideshowActive: Bool,
        overlayOwnsPhoneHero: Bool
    ) -> Bool {
        !photoLive && !toolSelected && !slideshowActive && !overlayOwnsPhoneHero
    }

    /// Whether a live overlay exists only on the phone hero.
    ///
    /// A Live Poll card taking that hero has to end the overlay, the same
    /// hand-off a photo tap makes through `present`; otherwise the website
    /// (or countdown, camera, PDF) tile keeps its red stroke with nothing
    /// showing it. On a projector the overlay keeps its own screen and the
    /// Practice / Start chrome is phone-only, so nothing is retired.
    ///
    /// - Parameters:
    ///   - isOverlayLive: Any overlay is the presentation source.
    ///   - displayConnected: AirPlay / HDMI has an attached scene to render it.
    ///   - isQuestPollLive: The overlay is the poll's own projector page, which
    ///     the room branch of `selectLivePoll` already owns.
    static func overlayOwnsPhoneHero(
        isOverlayLive: Bool,
        displayConnected: Bool,
        isQuestPollLive: Bool
    ) -> Bool {
        isOverlayLive && !displayConnected && !isQuestPollLive
    }

    /// Which Live Poll card owns idle chrome: an active Practice wins over a
    /// pending gate, and either only counts inside the Show it belongs to.
    ///
    /// The Show scoping is load-bearing. Practice outlives closing a Show, so
    /// without it another Show's deck painted into this Show's hero — the same
    /// scoping `isLivePollPhoneHeroActive` and the cue ribbon already apply.
    ///
    /// - Parameters:
    ///   - practiceShowId: Show owning the Practice card, if any.
    ///   - gateShowId: Show owning the card waiting on Practice / Start, if any.
    static func idleMembership(
        practiceMembershipId: UUID?,
        practiceShowId: UUID?,
        gateMembershipId: UUID?,
        gateShowId: UUID?,
        openShowId: UUID?
    ) -> (membershipId: UUID, isPracticing: Bool)? {
        guard let openShowId else { return nil }
        if let id = practiceMembershipId, practiceShowId == openShowId {
            return (id, true)
        }
        if let id = gateMembershipId, gateShowId == openShowId {
            return (id, false)
        }
        return nil
    }
}

extension LibraryGridViewController {

    /// True when no photo, Show tool, slideshow, or phone-hero overlay has program.
    var canShowLivePollIdleChrome: Bool {
        LivePollIdleChrome.isAvailable(
            photoLive: store.currentId != nil,
            toolSelected: isLogoSelected || isScreensaverSelected || isBlackSelected,
            slideshowActive: SlideshowPlaybackController.shared.activeSlideshowId != nil,
            overlayOwnsPhoneHero: livePollGateBlockedByPhoneHeroOverlay
        )
    }

    /// A countdown, website, camera, or PDF is live with no display to sit on, so
    /// the phone hero is its only output and the gate must not paint over it.
    ///
    /// The poll's own room is excluded — that overlay *is* the poll, and the
    /// callers that matter already return early on `isQuestPollLive`.
    ///
    /// Reads `isConnected`, not `projectorAvailable`: ending the overlay is a
    /// side effect on real output, and an unattached scene is not showing it.
    var livePollGateBlockedByPhoneHeroOverlay: Bool {
        let mgr = ExternalDisplayManager.shared
        return LivePollIdleChrome.overlayOwnsPhoneHero(
            isOverlayLive: mgr.isOverlayLive,
            displayConnected: mgr.isConnected,
            isQuestPollLive: mgr.isQuestPollLive
        )
    }

    /// Ends the overlay that owns the phone hero so a Live Poll card can take it.
    ///
    /// Photo, PDF, camera, and countdown taps all reach `present`, which ends
    /// the web overlay and drops the website tile's stroke. Arming the gate or
    /// Practice never presented anything, so in Practice Mode the website stayed
    /// live under the poll — red stroke and all. `clear()` notifies like
    /// `present` does, so the grid, hero, and phone browser see the same end.
    ///
    /// Call this before resetting the tool flags: the overlay-end notification
    /// re-derives the Screensaver fallback selection, which would otherwise sit
    /// under the gate as a selected tool and hide it.
    func retirePhoneHeroOverlayForLivePoll() {
        guard livePollGateBlockedByPhoneHeroOverlay else { return }
        ExternalDisplayManager.shared.clear()
    }

    /// True while the hero shows Practice / Start or the Practice deck instead of
    /// what is on program. Countdown ticks must not repaint the clock over it.
    var showsLivePollIdleHeader: Bool {
        if ExternalDisplayManager.shared.isQuestPollLive { return false }
        guard canShowLivePollIdleChrome else { return false }
        return livePollIdleCard != nil
    }

    /// Practice preview or Practice/Start gate when a card is selected idle.
    func applyLivePollIdleHeaderIfNeeded() -> Bool {
        if ExternalDisplayManager.shared.isQuestPollLive { return false }
        guard canShowLivePollIdleChrome, let card = livePollIdleCard else {
            liveHeader.hideLivePollGate()
            return false
        }
        if card.isPracticing {
            applyLivePollPracticeHeader(card.item)
        } else {
            liveHeader.showLivePollGate(
                title: card.item.title,
                onPractice: { [weak self] in self?.practiceLivePoll(card.item) },
                onStart: { [weak self] in self?.startLivePoll(card.item) }
            )
        }
        return true
    }

    /// Retires a pending gate when another tile takes the hero.
    func dismissLivePollGateIfNeeded(for item: ShowGridItem) {
        guard livePollGateMembershipId != nil else { return }
        switch item {
        case .livePoll, .unresolved, .add:
            return
        default:
            livePollGateMembershipId = nil
        }
    }

    // MARK: - Private

    /// Card driving idle chrome, scoped to the open Show — see `idleMembership`.
    private var livePollIdleCard: (item: ShowLivePoll, isPracticing: Bool)? {
        let polls = LivePollStore.shared
        let practiceId = QuestPollSessionStore.shared.practiceMembershipId
        let gateId = livePollGateMembershipId
        guard let idle = LivePollIdleChrome.idleMembership(
            practiceMembershipId: practiceId,
            practiceShowId: practiceId.flatMap { polls.poll(id: $0)?.showId },
            gateMembershipId: gateId,
            gateShowId: gateId.flatMap { polls.poll(id: $0)?.showId },
            openShowId: openShowId
        ), let item = polls.poll(id: idle.membershipId) else { return nil }
        return (item, idle.isPracticing)
    }

    /// Phone-hero deck preview, labelled Practice and without the LIVE chip.
    private func applyLivePollPracticeHeader(_ item: ShowLivePoll) {
        liveHeader.hideLivePollGate()
        let page = QuestPollConfig.previewPage(pollId: item.pollId)
        let canShow = !WarmWebSessionPool.shared.isAdopted(pageId: page.id)
        if canShow {
            WarmWebSessionPool.shared.warmIfNeeded(for: page)
        }
        liveHeader.configureOverlay(
            title: "\(item.title) · Practice",
            systemImage: "chart.bar.fill",
            fillColor: .mediaPlaceholder,
            keepWebPreview: canShow,
            showsLiveBadge: false
        )
        if canShow {
            liveHeader.showWebPreview(pageId: page.id)
        }
        liveHeader.updatePlayback(PlaybackState())
    }
}
