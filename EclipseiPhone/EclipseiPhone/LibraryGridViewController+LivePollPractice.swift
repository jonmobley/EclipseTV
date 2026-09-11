//
//  LibraryGridViewController+LivePollPractice.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Whether the phone hero may show a Live Poll Practice preview.
///
/// With a projector attached the preview is phone-only: a live website,
/// countdown, camera, or PDF keeps its own screen while the host rehearses, so
/// it does not block Practice. Anything the phone hero itself is showing —
/// a photo, a Show tool, a running slideshow, or an overlay in Practice Mode —
/// does take the hero back.
enum LivePollPracticeChrome {

    /// - Parameters:
    ///   - photoLive: A library still or video is the live item.
    ///   - toolSelected: Blackout, Logo, or Screensaver is selected.
    ///   - slideshowActive: A slideshow is playing.
    ///   - overlayOwnsPhoneHero: A live overlay (countdown, website, camera, PDF)
    ///     has no display to sit on, so the phone hero is the only place it
    ///     exists. Painting the preview over it retired the overlay from the
    ///     sole output while its tile still read live.
    static func isAvailable(
        photoLive: Bool,
        toolSelected: Bool,
        slideshowActive: Bool,
        overlayOwnsPhoneHero: Bool
    ) -> Bool {
        !photoLive && !toolSelected && !slideshowActive && !overlayOwnsPhoneHero
    }

    /// Which Live Poll card owns the Practice preview, counting only inside the
    /// Show it belongs to.
    ///
    /// The Show scoping is load-bearing. Practice outlives closing a Show, so
    /// without it another Show's deck painted into this Show's hero — the same
    /// scoping `isLivePollPhoneHeroActive` and the cue ribbon already apply.
    ///
    /// - Parameter practiceShowId: Show owning the Practice card, if any.
    static func practiceMembership(
        practiceMembershipId: UUID?,
        practiceShowId: UUID?,
        openShowId: UUID?
    ) -> UUID? {
        guard let openShowId, let id = practiceMembershipId,
              practiceShowId == openShowId else { return nil }
        return id
    }
}

extension LibraryGridViewController {

    /// True when no photo, Show tool, slideshow, or phone-hero overlay has program.
    var canShowLivePollPracticeChrome: Bool {
        LivePollPracticeChrome.isAvailable(
            photoLive: store.currentId != nil,
            toolSelected: isLogoSelected || isScreensaverSelected || isBlackSelected,
            slideshowActive: SlideshowPlaybackController.shared.activeSlideshowId != nil,
            overlayOwnsPhoneHero: livePollPracticeBlockedByPhoneHeroOverlay
        )
    }

    /// A countdown, website, camera, or PDF is live with no display to sit on, so
    /// the phone hero is its only output and Practice must not take it.
    ///
    /// The poll's own room is excluded — that overlay *is* the poll, and the
    /// callers that matter already return early on `isQuestPollLive`.
    var livePollPracticeBlockedByPhoneHeroOverlay: Bool {
        let mgr = ExternalDisplayManager.shared
        return mgr.isOverlayLive && !mgr.isConnected && !mgr.isQuestPollLive
    }

    /// True while the hero shows the Practice deck instead of what is on
    /// program. Countdown ticks must not repaint the clock over it.
    var showsLivePollPracticeHeader: Bool {
        if ExternalDisplayManager.shared.isQuestPollLive { return false }
        guard canShowLivePollPracticeChrome else { return false }
        return livePollPracticeCard != nil
    }

    /// Practice preview when a card in this Show is rehearsing.
    func applyLivePollPracticeHeaderIfNeeded() -> Bool {
        if ExternalDisplayManager.shared.isQuestPollLive { return false }
        guard canShowLivePollPracticeChrome, let card = livePollPracticeCard else {
            return false
        }
        applyLivePollPracticeHeader(card)
        return true
    }

    // MARK: - Private

    /// Card in Practice, scoped to the open Show — see `practiceMembership`.
    private var livePollPracticeCard: ShowLivePoll? {
        let polls = LivePollStore.shared
        let practiceId = QuestPollSessionStore.shared.practiceMembershipId
        guard let membershipId = LivePollPracticeChrome.practiceMembership(
            practiceMembershipId: practiceId,
            practiceShowId: practiceId.flatMap { polls.poll(id: $0)?.showId },
            openShowId: openShowId
        ) else { return nil }
        return polls.poll(id: membershipId)
    }

    /// Phone-hero deck preview, labelled Practice and without the LIVE chip.
    private func applyLivePollPracticeHeader(_ item: ShowLivePoll) {
        let page = QuestPollConfig.previewPage(pollId: item.pollId)
        let canShow = !WarmWebSessionPool.shared.isAdopted(pageId: page.id)
        if canShow {
            WarmWebSessionPool.shared.warmIfNeeded(for: page)
        }
        liveHeader.configureOverlay(
            title: "\(item.title) · Practice",
            systemImage: "chart.bar.fill",
            fillColor: UIColor(white: 0.12, alpha: 1),
            keepWebPreview: canShow,
            showsLiveBadge: false
        )
        if canShow {
            liveHeader.showWebPreview(pageId: page.id)
        }
        liveHeader.updatePlayback(PlaybackState())
    }
}
