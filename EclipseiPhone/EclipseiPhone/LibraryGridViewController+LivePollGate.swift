//
//  LibraryGridViewController+LivePollGate.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Whether the phone hero may show Live Poll Practice / Start chrome.
///
/// That chrome is phone-only: a live website, countdown, camera, or PDF keeps
/// the projector until the host taps Start, so a live overlay is deliberately
/// not an input here. Program picks that the phone itself owns — a photo, a
/// Show tool, or a running slideshow — do take the hero back.
enum LivePollIdleChrome {

    /// - Parameters:
    ///   - photoLive: A library still or video is the live item.
    ///   - toolSelected: Blackout, Logo, or Screensaver is selected.
    ///   - slideshowActive: A slideshow is playing.
    static func isAvailable(
        photoLive: Bool,
        toolSelected: Bool,
        slideshowActive: Bool
    ) -> Bool {
        !photoLive && !toolSelected && !slideshowActive
    }
}

extension LibraryGridViewController {

    /// True when no photo, Show tool, or slideshow has taken program.
    var canShowLivePollIdleChrome: Bool {
        LivePollIdleChrome.isAvailable(
            photoLive: store.currentId != nil,
            toolSelected: isLogoSelected || isScreensaverSelected || isBlackSelected,
            slideshowActive: SlideshowPlaybackController.shared.activeSlideshowId != nil
        )
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

    /// Card driving idle chrome: an active Practice wins over a pending gate.
    private var livePollIdleCard: (item: ShowLivePoll, isPracticing: Bool)? {
        if let membershipId = QuestPollSessionStore.shared.practiceMembershipId,
           let item = LivePollStore.shared.poll(id: membershipId) {
            return (item, true)
        }
        if let membershipId = livePollGateMembershipId,
           let item = LivePollStore.shared.poll(id: membershipId) {
            return (item, false)
        }
        return nil
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
