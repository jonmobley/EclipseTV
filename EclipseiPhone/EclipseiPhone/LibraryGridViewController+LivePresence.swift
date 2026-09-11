//
//  LibraryGridViewController+LivePresence.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Presence

extension LibraryGridViewController {
    /// Open Show asked to show the live preview hero with no AirPlay / HDMI / EclipseTV.
    var prefersDisconnectedLivePreview: Bool {
        isShowMode && (openShow?.previewsWhenDisconnected == true)
    }

    /// Tap marks live (red) when AirPlay, EclipseTV, or Practice Mode is on.
    ///
    /// Otherwise the Show is Preview-only: no live hero, and taps open the
    /// on-device gallery / browser instead of going live.
    var hasLiveOutputDestination: Bool {
        LiveOutputRouting.canMarkLive(practiceMode: prefersDisconnectedLivePreview)
    }

    /// Locked live output, or no AirPlay / Practice destination: tap Preview.
    var prefersPhonePreviewOnTap: Bool {
        LiveOutputRouting.prefersPhonePreviewOnTap(
            isLiveOutputLocked: isLiveOutputLocked,
            hasOutputDestination: hasLiveOutputDestination
        )
    }

    /// Live hero on an open Show: a real destination, Practice Mode, a Live
    /// Poll the phone is hosting with no display attached, or Camera live
    /// (tile tap always goes live; the controller opens from this preview).
    var showsLiveHero: Bool {
        isShowMode && LiveOutputRouting.showsLiveHero(
            hasOutputDestination: hasLiveOutputDestination,
            isLivePollPhoneHeroActive: isLivePollPhoneHeroActive,
            isCameraModeActive: ExternalDisplayManager.shared.isCameraModeActive
        )
    }

    /// Gate, Practice preview, or this Show's active room — show the hero so
    /// the host can run the poll on the phone when AirPlay / HDMI are down.
    var isLivePollPhoneHeroActive: Bool {
        guard isShowMode, let openShowId else { return false }
        if livePollGateMembershipId != nil { return true }
        let store = QuestPollSessionStore.shared
        if let practiceId = store.practiceMembershipId,
           LivePollStore.shared.poll(id: practiceId)?.showId == openShowId {
            return true
        }
        if store.session != nil,
           let membershipId = store.membershipId,
           LivePollStore.shared.poll(id: membershipId)?.showId == openShowId {
            return true
        }
        return false
    }
}
