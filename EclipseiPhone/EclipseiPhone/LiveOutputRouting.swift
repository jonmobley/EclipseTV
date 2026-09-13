//
//  LiveOutputRouting.swift
//  Eclipse
//
//  Copyright © 2026 Moxie LLC. All rights reserved.
//

import UIKit

/// Tap goes live (red) with AirPlay, EclipseTV, Practice Mode, or a remote director.
enum LiveOutputRouting {

    /// The one projector signal every routing decision here reads.
    ///
    /// `isAirPlayAvailable` is deliberately wider than `isConnected`: on iOS 27+
    /// the scene accessory reports a display before its scene attaches, and
    /// `present(_:)` attaches on demand. Mixing the two made the same question
    /// disagree with itself — the Show marked taps live and let websites go live
    /// off `isAirPlayAvailable` while Live Poll refused with "needs AirPlay or
    /// HDMI" off `isConnected`.
    ///
    /// Affordances (badges, gates, what a tap means) belong here. Side effects
    /// that drive real hardware — parking EclipseTV, director election, mirroring
    /// the camera — must keep reading `isConnected`, since an unattached scene
    /// cannot render and parking the TV for it just blanks the room.
    @MainActor
    static var projectorAvailable: Bool {
        ExternalDisplayManager.shared.isAirPlayAvailable
    }

    /// Live when a display, EclipseTV, Practice Mode, or a remote director is available.
    static func canMarkLive(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool,
        isRemoteOperator: Bool = false
    ) -> Bool {
        airPlayConnected || eclipseTVOnline || practiceMode || isRemoteOperator
    }

    /// Live using the current AirPlay / EclipseTV / remote-operator state.
    @MainActor
    static func canMarkLive(practiceMode: Bool) -> Bool {
        canMarkLive(
            airPlayConnected: projectorAvailable,
            eclipseTVOnline: TVLibraryStore.shared.isOnline,
            practiceMode: practiceMode,
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator
        )
    }

    /// Tap opens on-device Preview when live is locked or there is no destination.
    static func prefersPhonePreviewOnTap(
        isLiveOutputLocked: Bool,
        hasOutputDestination: Bool
    ) -> Bool {
        isLiveOutputLocked || !hasOutputDestination
    }

    /// Open-Show live hero: a destination, a phone-hosted Live Poll, or Camera live.
    ///
    /// Camera tile tap always goes live, even with no AirPlay / Practice
    /// destination, so the hero has to appear for the preview → controller tap.
    static func showsLiveHero(
        hasOutputDestination: Bool,
        isLivePollPhoneHeroActive: Bool,
        isCameraModeActive: Bool
    ) -> Bool {
        hasOutputDestination || isLivePollPhoneHeroActive || isCameraModeActive
    }

    /// Web overlays (Live Poll / websites) only reach AirPlay / HDMI or Practice.
    /// Linked EclipseTV stays on the companion library and cannot show a WKWebView.
    static func canPresentWebOverlay(
        airPlayConnected: Bool,
        practiceMode: Bool
    ) -> Bool {
        airPlayConnected || practiceMode
    }

    /// Web overlay using the current AirPlay / Practice state.
    @MainActor
    static func canPresentWebOverlay(practiceMode: Bool) -> Bool {
        canPresentWebOverlay(
            airPlayConnected: projectorAvailable,
            practiceMode: practiceMode
        )
    }

    /// Live Poll can use the phone as projector when nothing else is connected.
    /// Linked EclipseTV still cannot render the page, so that path needs AirPlay
    /// / HDMI or Practice Mode.
    static func canHostLivePoll(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool
    ) -> Bool {
        if airPlayConnected || practiceMode { return true }
        return !eclipseTVOnline
    }

    /// Live Poll hosting using the current projector / EclipseTV state.
    @MainActor
    static func canHostLivePoll(practiceMode: Bool) -> Bool {
        canHostLivePoll(
            airPlayConnected: projectorAvailable,
            eclipseTVOnline: TVLibraryStore.shared.isOnline,
            practiceMode: practiceMode
        )
    }

    /// Red LIVE chip on the Live Poll hero only when an external display owns it.
    static func showsLivePollLiveBadge(externalDisplayConnected: Bool) -> Bool {
        externalDisplayConnected
    }

    /// Live Poll LIVE chip using the current projector state.
    @MainActor
    static func showsLivePollLiveBadge() -> Bool {
        showsLivePollLiveBadge(externalDisplayConnected: projectorAvailable)
    }

    /// Screensaver is the live grid item when a destination is up and nothing else is.
    static func isScreensaverFallbackLive(
        hasOutputDestination: Bool,
        isOverlayLive: Bool,
        isJoinedLive: Bool,
        isBlackSelected: Bool,
        isLogoSelected: Bool,
        hasLibraryLiveItem: Bool,
        hasLiveSlideshow: Bool
    ) -> Bool {
        hasOutputDestination
            && !isOverlayLive
            && !isJoinedLive
            && !isBlackSelected
            && !isLogoSelected
            && !hasLibraryLiveItem
            && !hasLiveSlideshow
    }

    /// Replace/reset updates AirPlay only when that tool is already live.
    static func shouldRefreshLiveAfterReplace(isToolLive: Bool) -> Bool {
        isToolLive
    }

    /// Phone hero plays library video only when it is the output (Practice Mode).
    static func phoneHeroPlaysLibraryVideo(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        practiceMode: Bool,
        isRemoteOperator: Bool = false
    ) -> Bool {
        practiceMode && !airPlayConnected && !eclipseTVOnline && !isRemoteOperator
    }

    /// Grey program monitor when library video is live on AirPlay, EclipseTV, or remote.
    static func usesRemoteVideoMonitor(
        isVideo: Bool,
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        isRemoteOperator: Bool = false
    ) -> Bool {
        isVideo && (airPlayConnected || eclipseTVOnline || isRemoteOperator)
    }

    /// LIVE overlay on the big preview: HDMI / AirPlay / EclipseTV / remote operator.
    /// Practice Mode still shows the hero, but it is not program output.
    static func showsHeroLiveBadge(
        airPlayConnected: Bool,
        eclipseTVOnline: Bool,
        isRemoteOperator: Bool = false
    ) -> Bool {
        airPlayConnected || eclipseTVOnline || isRemoteOperator
    }

    /// LIVE overlay using the current HDMI / AirPlay / EclipseTV / remote state.
    @MainActor
    static func showsHeroLiveBadge() -> Bool {
        showsHeroLiveBadge(
            airPlayConnected: projectorAvailable,
            eclipseTVOnline: TVLibraryStore.shared.isOnline,
            isRemoteOperator: ShowLiveSession.shared.isRemoteOperator
        )
    }
}
