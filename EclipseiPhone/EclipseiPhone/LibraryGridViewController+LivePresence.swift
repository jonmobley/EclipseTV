//
//  LibraryGridViewController+LivePresence.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

// MARK: - Live Presence

extension LibraryGridViewController {
    /// Practice Mode: an open Show always rehearses with no AirPlay / HDMI /
    /// EclipseTV (live hero, Lock / Blackout), the way the Mac always shows its
    /// program. It used to be a per-Show switch; the owner made it permanent
    /// (2026-11-25). Home has no live hero, so it stays off there.
    var prefersDisconnectedLivePreview: Bool {
        isShowMode
    }

    /// Tap marks live when AirPlay, EclipseTV, Practice Mode (any open Show) or a
    /// remote director is available.
    ///
    /// Otherwise (Home with nothing connected) taps open the on-device gallery /
    /// browser instead of going live.
    var hasLiveOutputDestination: Bool {
        LiveOutputRouting.canMarkLive(practiceMode: prefersDisconnectedLivePreview)
    }

    /// Locked live output, Blackout holding, or no AirPlay / Practice destination:
    /// a tile tap opens Preview instead of going live.
    var prefersPhonePreviewOnTap: Bool {
        LiveOutputRouting.prefersPhonePreviewOnTap(
            isLiveOutputLocked: isLiveOutputLocked,
            hasOutputDestination: hasLiveOutputDestination,
            isBlackoutHolding: isBlackoutHolding
        )
    }

    /// Same as `prefersPhonePreviewOnTap`, minus the Blackout hold.
    ///
    /// For deliberate go-live paths (an operator's select, ⋯ options, a cued item
    /// leaving Blackout) that must not turn into a Preview on this phone.
    var prefersPhonePreviewIgnoringBlackout: Bool {
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

    /// Practice preview or this Show's active room — show the hero so the host
    /// can run the poll on the phone when AirPlay / HDMI are down.
    var isLivePollPhoneHeroActive: Bool {
        guard isShowMode, let openShowId else { return false }
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
